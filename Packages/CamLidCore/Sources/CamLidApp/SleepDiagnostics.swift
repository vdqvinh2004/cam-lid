import Foundation
import IOKit.pwr_mgt
import CamLidCore

/// Read-only, on-demand inspection. Never creates or releases power assertions.
public struct SleepAssertion: Sendable, Equatable, Identifiable {
    public let id: String
    public let pid: Int
    public let owner: String
    public let type: String
    public let reason: String

    public var holdsSystemSleep: Bool {
        ["PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "PreventSystemSleep"].contains(type)
    }
    public var holdsDisplaySleep: Bool { type == "PreventUserIdleDisplaySleep" }
    public var effect: String {
        switch type {
        case "PreventUserIdleSystemSleep": return "Keeps system awake"
        case "PreventUserIdleDisplaySleep": return "Keeps system and display awake"
        case "PreventSystemSleep": return "System sleep request"
        case "UserIsActive": return "Recent input postpones display sleep"
        case "ExternalMedia": return "External device activity"
        default: return "Other power activity"
        }
    }
}

public struct SleepDiagnosticsSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let assertions: [SleepAssertion]
    public let error: String?

    public init(capturedAt: Date = Date(), assertions: [SleepAssertion] = [], error: String? = nil) {
        self.capturedAt = capturedAt; self.assertions = assertions; self.error = error
    }

    public static func read() -> Self {
        var processes: Unmanaged<CFDictionary>?
        var status: Unmanaged<CFDictionary>?
        let processResult = IOPMCopyAssertionsByProcess(&processes)
        let statusResult = IOPMCopyAssertionsStatus(&status)
        // Copy APIs transfer ownership, including any result returned on error.
        let processDictionary = processes?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        let statusDictionary = status?.takeRetainedValue() as? [String: NSNumber]
        guard processResult == kIOReturnSuccess, statusResult == kIOReturnSuccess,
              let processDictionary, let statusDictionary else {
            return Self(error: "macOS sleep requests could not be read (\(processResult), \(statusResult)). Try Refresh.")
        }
        return Self(assertions: project(processes: processDictionary, status: statusDictionary))
    }

    static func project(processes: [NSNumber: [[String: Any]]], status: [String: NSNumber]) -> [SleepAssertion] {
        var result: [SleepAssertion] = []
        for (pid, entries) in processes {
            for (index, entry) in entries.enumerated() {
                guard let level = entry["AssertLevel"] as? NSNumber, level.intValue != 0,
                      let type = entry["AssertType"] as? String,
                      (status[type]?.intValue ?? 0) != 0 else { continue }
                let assertionID = (entry["AssertionId"] as? NSNumber)?.stringValue ?? "row-\(index)"
                let owner = entry["Process Name"] as? String ?? "Process \(pid.intValue)"
                let name = entry["AssertName"] as? String ?? type
                let detail = entry["HumanReadableReason"] as? String ?? entry["Details"] as? String
                result.append(SleepAssertion(id: "\(pid)-\(assertionID)", pid: pid.intValue, owner: owner,
                    type: type, reason: detail.map { $0 == name ? name : name + "\n" + $0 } ?? name))
            }
        }
        return result.sorted {
            if $0.holdsSystemSleep != $1.holdsSystemSleep { return $0.holdsSystemSleep }
            if $0.owner != $1.owner { return $0.owner.localizedStandardCompare($1.owner) == .orderedAscending }
            return $0.id < $1.id
        }
    }
}

/// One bounded on-demand worker; a stuck IOKit read cannot spawn more workers.
/// Only fixed read-only pmset queries. Raw reasons/device labels never leave collection.
public final class SleepDiagnosticReader: @unchecked Sendable {
    public static let shared = SleepDiagnosticReader()
    private let lock = NSLock()
    private var busy = false
    private let timeout: Double
    private let nativeReader: @Sendable () -> SleepDiagnosticsSnapshot
    private let powerReader: @Sendable () throws -> DiagnosticSnapshot
    public convenience init() {
        self.init(timeout: 4.5, nativeReader: { SleepDiagnosticsSnapshot.read() }, powerReader: {
            let executable = URL(fileURLWithPath: "/usr/bin/pmset")
            let settings = try OrcaPoller.run(executable: executable, arguments: ["-g"], timeout: 0.8)
            let assertions = try OrcaPoller.run(executable: executable, arguments: ["-g", "assertions"], timeout: 0.8,
                maximumBytes: 65_536 - settings.count)
            guard settings.count + assertions.count <= 65_536 else { throw OrcaPollError.tooLarge }
            return Self.powerCategories(settings: String(decoding: settings, as: UTF8.self),
                assertions: String(decoding: assertions, as: UTF8.self))
        })
    }
    init(timeout: Double, nativeReader: @escaping @Sendable () -> SleepDiagnosticsSnapshot,
         powerReader: @escaping @Sendable () throws -> DiagnosticSnapshot) {
        self.timeout = timeout; self.nativeReader = nativeReader; self.powerReader = powerReader
    }
    public func snapshot() async -> DiagnosticSnapshot {
        let admitted = lock.withLock { if busy { return false }; busy = true; return true }
        guard admitted else { return DiagnosticSnapshot(coverage: ["userAssertions": .unavailable], errors: ["collectionBusy"]) }
        return await withCheckedContinuation { continuation in
            let reply = DiagnosticCompletion(continuation)
            DispatchQueue.global(qos: .utility).async { [self] in
                let began = ContinuousTime.now
                let native = nativeReader()
                var result = DiagnosticSnapshot(observedAt: native.capturedAt,
                    coverage: ["userAssertions": native.error == nil ? .complete : .unavailable,
                               "aggregate": native.error == nil ? .complete : .unavailable,
                               "global": .unavailable, "kernel": .unavailable],
                    errors: native.error == nil ? [] : ["assertionsUnavailable"])
                result.blockers = native.assertions.prefix(256).map { assertion in
                    let effect = SleepEffect.assertion(assertion.type)
                    return DiagnosticBlocker(id: assertion.id, type: assertion.type, effect: effect,
                        source: "IOKit", owner: assertion.owner, pid: assertion.pid, explanation: effect.title)
                }
                if native.assertions.count > 256 {
                    result.coverage["userAssertions"] = .partial; result.errors.append("ownerRowsTruncated")
                }
                if ContinuousTime.now - began < 2 {
                    do {
                        let power = try powerReader()
                        result.coverage.merge(power.coverage) { _, new in new }
                        result.blockers += power.blockers
                        result.errors += power.errors
                    } catch { result.errors.append("powerCategoriesUnavailable") }
                } else { result.errors.append("powerCategoriesDeadline") }
                lock.withLock { busy = false }
                reply.finish(result)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                reply.finish(DiagnosticSnapshot(coverage: ["userAssertions": .unavailable,
                    "aggregate": .unavailable, "global": .unavailable, "kernel": .unavailable], errors: ["collectionTimedOut"]))
            }
        }
    }
    static func powerCategories(settings: String, assertions: String) -> DiagnosticSnapshot {
        var result = DiagnosticSnapshot(coverage: ["global": .unavailable, "kernel": .unavailable])
        if let line = settings.split(separator: "\n").first(where: { $0.split(whereSeparator: \.isWhitespace).first == "SleepDisabled" }),
           let value = line.split(whereSeparator: \.isWhitespace).last, ["0", "1"].contains(value) {
            result.coverage["global"] = .complete
            if value == "1" { result.blockers.append(DiagnosticBlocker(id: "global-sleepDisabled", type: "SleepDisabled",
                effect: .global, source: "pmset", explanation: "System-wide sleep is disabled. CamLid does not change this setting.")) }
        } else { result.errors.append("globalSettingUnknown") }
        if let line = assertions.split(separator: "\n").first(where: { $0.hasPrefix("Kernel Assertions:") }) {
            let value = line.dropFirst("Kernel Assertions:".count).trimmingCharacters(in: .whitespaces)
            if value == "None" || value == "0x0" { result.coverage["kernel"] = .complete }
            else if value.hasPrefix("0x"), let equals = value.firstIndex(of: "="),
                    let flags = UInt64(value[value.index(value.startIndex, offsetBy: 2)..<equals], radix: 16) {
                result.coverage["kernel"] = .complete
                if flags != 0 { result.blockers.append(DiagnosticBlocker(id: "kernel-requests", type: "KernelAssertions", effect: .kernel,
                    source: "pmset", explanation: "macOS reports active kernel or device sleep requests. No reliable process owner is available."))
                }
            } else { result.errors.append("kernelFormatUnknown") }
        } else { result.errors.append("kernelCoverageUnknown") }
        return result
    }
}
private final class DiagnosticCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DiagnosticSnapshot, Never>?
    init(_ continuation: CheckedContinuation<DiagnosticSnapshot, Never>) { self.continuation = continuation }
    func finish(_ result: DiagnosticSnapshot) {
        let pending = lock.withLock { let pending = continuation; continuation = nil; return pending }
        pending?.resume(returning: result)
    }
}
