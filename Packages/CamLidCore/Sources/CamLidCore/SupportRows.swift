import Foundation

/// A Mac model and OS build on which closed-lid actuation has passed an owner-approved attended trial.
public struct SupportRow: Equatable, Sendable {
    public let id: String
    public let model: String
    public let osBuild: String

    public init(id: String, model: String, osBuild: String) {
        self.id = id; self.model = model; self.osBuild = osBuild
    }
}

public enum QualifiedSupportRows {
    /// A row is added only with the owner's approval after the attended trial in
    /// specs/014-persistent-helper/g2-trial.md. Other Macs need the user's "untested configuration" acceptance.
    public static let rows: [SupportRow] = [
        // G2 passed 2026-10-31 (trials 1–7 and 9; trial 8 deferred); owner approved the row the same day.
        SupportRow(id: "mac17-3-26a434", model: "Mac17,3", osBuild: "26A434"),
    ]

    /// Strict (ADR 0003) is qualified separately: it uses an undocumented kernel interface, and an untested Mac
    /// cannot accept it. Mac17,3 / 26A434 passed experiments E1–E4 and E6 on 2026-10-31 (E5 not run).
    public static let strictRows: [SupportRow] = [
        SupportRow(id: "mac17-3-26a434", model: "Mac17,3", osBuild: "26A434"),
    ]

    public static func matching(model: String?, osBuild: String?, in table: [SupportRow] = rows) -> String? {
        guard let model, let osBuild else { return nil }
        return table.first { $0.model == model && $0.osBuild == osBuild }?.id
    }

    public static func currentSystem() -> (model: String?, osBuild: String?) {
        (sysctlString("hw.model"), sysctlString("kern.osversion"))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, (2...128).contains(size) else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// The user's explicit acceptance that closed lid may run on a Mac without a qualified row. Valid only for the exact
/// model and macOS build it was given on; a macOS update or another Mac asks again.
public struct UntestedAcknowledgement: Codable, Equatable, Sendable {
    public let model: String
    public let osBuild: String
    public let acceptedAt: Date

    public init(model: String, osBuild: String, acceptedAt: Date) {
        self.model = model; self.osBuild = osBuild; self.acceptedAt = acceptedAt
    }
}

/// Whether closed lid may ask the helper to hold power on this Mac (spec 014 FR-016).
public enum ClosedLidPermit: Equatable, Sendable {
    case qualified(rowID: String)
    case untestedAcknowledged
    case notPermitted

    public var allowsActuation: Bool { self != .notPermitted }

    public var statusCode: String {
        switch self {
        case .qualified(let id): "qualified:\(id)"
        case .untestedAcknowledged: "untestedAcknowledged"
        case .notPermitted: "notPermitted"
        }
    }

    public static func decide(model: String?, osBuild: String?, rows: [SupportRow] = QualifiedSupportRows.rows,
                              acknowledgement: UntestedAcknowledgement?) -> ClosedLidPermit {
        if let id = QualifiedSupportRows.matching(model: model, osBuild: osBuild, in: rows) { return .qualified(rowID: id) }
        guard let model, let osBuild, let acknowledgement,
              acknowledgement.model == model, acknowledgement.osBuild == osBuild else { return .notPermitted }
        return .untestedAcknowledged
    }
}

/// Another keep-awake app found on this Mac. `resetsSleepSetting` marks apps seen to undo `pmset disablesleep` set by
/// someone else (LidRun, found in G2), which interrupts closed lid; the others only keep the Mac awake alongside CamLid.
public struct KeepAwakeApp: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let resetsSleepSetting: Bool
    public init(name: String, resetsSleepSetting: Bool) { self.name = name; self.resetsSleepSetting = resetsSleepSetting }
}

/// Read-only detection of other keep-awake apps (spec 014 FR-019). CamLid never stops or changes them.
/// shortcut: a fixed list of well-known apps, helpers and `caffeinate`; extend it when another app is found.
public enum KeepAwakeApps {
    static let lidRun = KeepAwakeApp(name: "LidRun", resetsSleepSetting: true)
    public static let bundleIDs: [String: KeepAwakeApp] = [
        "com.if.Amphetamine": KeepAwakeApp(name: "Amphetamine", resetsSleepSetting: false),
        "info.marcel-dierkes.KeepingYouAwake": KeepAwakeApp(name: "KeepingYouAwake", resetsSleepSetting: false),
        "com.sindresorhus.Lungo": KeepAwakeApp(name: "Lungo", resetsSleepSetting: false),
        "com.lightheadsw.Caffeine": KeepAwakeApp(name: "Caffeine", resetsSleepSetting: false),
        "com.lidrun.app": lidRun,
        "com.lidwalk.app": KeepAwakeApp(name: "LidWalk", resetsSleepSetting: false),
    ]
    public static let helperLabels: [String: KeepAwakeApp] = [
        "com.lidrun.app.helper": lidRun,
        "com.lidwalk.helper": KeepAwakeApp(name: "LidWalk", resetsSleepSetting: false),
    ]
    public static let processNames: [String: KeepAwakeApp] = [
        "caffeinate": KeepAwakeApp(name: "caffeinate", resetsSleepSetting: false),
    ]

    /// One entry per app name, sorted; an app is marked as resetting if any of its sources is.
    public static func detect(runningBundleIDs: Set<String>, runningProcesses: Set<String>,
                              isRunning: (String) -> Bool) -> [KeepAwakeApp] {
        let found = bundleIDs.filter { runningBundleIDs.contains($0.key) }.map(\.value)
            + helperLabels.filter { isRunning($0.key) }.map(\.value)
            + processNames.filter { runningProcesses.contains($0.key) }.map(\.value)
        let byName = Dictionary(grouping: found, by: \.name)
        return byName.map { KeepAwakeApp(name: $0.key, resetsSleepSetting: $0.value.contains { $0.resetsSleepSetting }) }
            .sorted { $0.name < $1.name }
    }
}
