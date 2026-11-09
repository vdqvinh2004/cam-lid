import Foundation
import IOKit.pwr_mgt

/// The IOKit calls behind `KeepAwakeAssertion`, injected so tests can stand in for the power manager.
struct KeepAwakeSystem {
    /// Creates an assertion of this system's type, owned by this process; nil when macOS refuses it.
    var create: (String) -> IOPMAssertionID?
    var release: (IOPMAssertionID) -> Void
    /// Names of this process's own assertions of this system's type, read back from the power manager.
    var ownAssertionNames: () -> [String]

    static var live: KeepAwakeSystem { live(assertionType: "PreventUserIdleSystemSleep") }

    /// The live power manager for one assertion type. Spec 023 uses `PreventUserIdleDisplaySleep` for the display option.
    static func live(assertionType: String) -> KeepAwakeSystem {
        KeepAwakeSystem(
            create: { reason in
                var identifier = IOPMAssertionID(0)
                let result = IOPMAssertionCreateWithName(assertionType as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &identifier)
                return result == kIOReturnSuccess ? identifier : nil
            },
            release: { _ = IOPMAssertionRelease($0) },
            ownAssertionNames: {
                var processes: Unmanaged<CFDictionary>?
                let result = IOPMCopyAssertionsByProcess(&processes)
                // Copy APIs transfer ownership, including on error.
                let dictionary = processes?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
                guard result == kIOReturnSuccess, let dictionary else { return [] }
                return (dictionary[NSNumber(value: getpid())] ?? []).compactMap { entry in
                    (entry["AssertType"] as? String) == assertionType ? entry["AssertName"] as? String : nil
                }
            })
    }
}

/// CamLid's lid-open keep-awake (spec 018). One `PreventUserIdleSystemSleep` assertion owned by this process: it
/// needs no helper and no administrator password, and the kernel releases it if CamLid exits. It is verified only
/// after a read-back finds this process's own assertion. Closing the lid is not covered; that is the helper's job.
final class KeepAwakeAssertion {
    static let reason = "CamLid keeps this Mac awake while a session runs"
    /// The display option's assertion (spec 023). Read back by its own reason, so it is never mistaken for the system one.
    static let displayReason = "CamLid keeps the display on while a session runs"
    /// While held, the assertion is read back this often, so one that disappears is reported.
    static let verifyEverySeconds = 15.0

    private let system: KeepAwakeSystem
    private let assertionReason: String
    private var assertionID: IOPMAssertionID?
    private var lastVerifiedAt = -Double.infinity
    private(set) var verified = false
    private(set) var issue: String?

    init(system: KeepAwakeSystem = .live, reason: String = KeepAwakeAssertion.reason) {
        self.system = system
        self.assertionReason = reason
    }

    var held: Bool { assertionID != nil }

    /// Holds the assertion while `wanted` is true, releases it otherwise, and re-reads it while held.
    func reconcile(wanted: Bool, now: Double) {
        guard wanted else {
            release()
            return
        }
        if assertionID == nil {
            guard let identifier = system.create(assertionReason) else {
                verified = false
                issue = "createFailed"
                return
            }
            assertionID = identifier
            verify(now: now)
        } else if now - lastVerifiedAt >= Self.verifyEverySeconds {
            verify(now: now)
        }
    }

    func release() {
        if let assertionID { system.release(assertionID) }
        assertionID = nil
        verified = false
        issue = nil
    }

    private func verify(now: Double) {
        lastVerifiedAt = now
        verified = system.ownAssertionNames().contains(assertionReason)
        issue = verified ? nil : "readBackMissing"
    }
}

/// Spec 023 (D2): whether sessions keep the display on. The setting is read while no session runs and held until the
/// session ends, so a change in Settings applies to the next session.
struct DisplaySleepChoice {
    private(set) var keepsDisplayOn = false

    mutating func observe(sessionActive: Bool, displaySleepAllowed: Bool) {
        guard !sessionActive else { return }
        keepsDisplayOn = !displaySleepAllowed
    }
}
