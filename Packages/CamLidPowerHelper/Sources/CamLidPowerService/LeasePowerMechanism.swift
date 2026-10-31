import Foundation
@_spi(TestInputs) import LidNativeAdapter

public enum CleanupEvidence: Sendable { case verifiedReadback, callsAcknowledgedOnly }

/// A read-only observation of the system-wide policy, never ownership of the shared lid bit.
public enum ForeignPolicyObservation: Sendable, Equatable {
    case clear
    case conflicted
    case unreadable
}

/// Actual OS-boundary semantics, not a fabricated shared-bit getter.
public protocol LeasePowerMechanism: AnyObject {
    var family: String { get }
    var maximumSessionSeconds: Int { get }
    var leaseSeconds: Double { get }
    var applyAcknowledged: Bool { get }
    /// True when the policy this mechanism sets survives a reboot (global `SleepDisabled`), so an
    /// acknowledged enable from a previous boot may be restored from the journal.
    var restoresOwnedPolicyAfterReboot: Bool { get }
    /// True when the policy lives in kernel memory (the clamshell bit): a restart clears it, so a record from a
    /// previous boot needs no write, and clearing it with the lid closed sleeps the Mac through the kernel.
    var restartClearsPolicy: Bool { get }
    /// True when no read-back exists and an acknowledged clear call is the restore (ADR 0003): the next session
    /// may start and any process may finish an interrupted restore. Never true for the frozen lid-specific path.
    var acknowledgedClearIsRestore: Bool { get }
    func admissionAllowed() throws -> Bool
    func apply(remainingNanos: UInt64, episodeID: UUID) throws
    func prepareRenewal(remainingNanos: UInt64, episodeID: UUID) throws
    func completeRenewal() throws
    /// nil means there is no trustworthy active-state getter, not Idle or restored.
    func readApplied() throws -> Bool?
    /// Observe a policy that this mechanism does not own. Must be implemented explicitly so a
    /// new mechanism cannot silently omit the coexistence check.
    func readForeignPolicy() throws -> ForeignPolicyObservation
    func clear() throws -> CleanupEvidence
    func discardOwnedResourcesAfterFailedApply() throws
    func releaseOwnedResourcesAfterFailedRestore()
}

public extension LeasePowerMechanism {
    var leaseSeconds: Double { PowerLeaseService.leaseSeconds }
    var restoresOwnedPolicyAfterReboot: Bool { false }
    var restartClearsPolicy: Bool { false }
    var acknowledgedClearIsRestore: Bool { false }
    func prepareRenewal(remainingNanos: UInt64, episodeID: UUID) throws {}
    func completeRenewal() throws {}
    func discardOwnedResourcesAfterFailedApply() throws {}
    func releaseOwnedResourcesAfterFailedRestore() {}
}

final class GlobalSleepMechanism: LeasePowerMechanism {
    static let familyName = "pmset-global-v1"
    let family = familyName
    let maximumSessionSeconds = PowerLeaseService.maximumSessionSeconds
    private let backend: any SleepOverrideBackend
    private(set) var applyAcknowledged = false
    let restoresOwnedPolicyAfterReboot = true
    init(_ backend: any SleepOverrideBackend) { self.backend = backend }
    func admissionAllowed() throws -> Bool { try !backend.readDisabled() }
    func apply(remainingNanos: UInt64, episodeID: UUID) throws {
        applyAcknowledged = false
        try backend.setDisabled(true)
        applyAcknowledged = true
    }
    func readApplied() throws -> Bool? { try backend.readDisabled() }
    func readForeignPolicy() throws -> ForeignPolicyObservation { .clear }
    func clear() throws -> CleanupEvidence {
        // Write the default before reading: `pmset -g` can fail while powerd is busy (it did during shutdown in
        // G2 trial 7) and must not stop the restore. Writing 0 when it is already 0 is harmless.
        try backend.setDisabled(false)
        guard try !backend.readDisabled() else { throw PowerServiceFailure.backend }
        applyAcknowledged = false
        return .verifiedReadback
    }
}

/// A lab-only single-episode mechanism. Cleanup acknowledgement cannot authorize re-arm.
/// Existing shared-mask ownership/expiry limitations remain, even with independent idle timeout.
public final class LidOnlyLeaseMechanism: LeasePowerMechanism {
    public static let bestEffortMaximumSessionSeconds = 15 * 60
    public let family = "lid-specific-v1"
    public let maximumSessionSeconds: Int
    public let leaseSeconds = 24.0
    private let make: () throws -> LidSpecificMechanism
    private let baselineAllowsLidSleep: () throws -> Bool
    private let foreignPolicyProbe: () throws -> ForeignPolicyObservation
    private var control: LidSpecificMechanism?
    public var applyAcknowledged: Bool { control?.suppressionAcknowledged == true }

    public init(maximumSessionSeconds: Int = 24,
                make: @escaping () throws -> LidSpecificMechanism,
                baselineAllowsLidSleep: @escaping () throws -> Bool,
                foreignPolicy: @escaping () throws -> ForeignPolicyObservation
                    = LidOnlyLeaseMechanism.observeNativeGlobalPolicy) {
        self.maximumSessionSeconds = maximumSessionSeconds
        self.make = make
        self.baselineAllowsLidSleep = baselineAllowsLidSleep
        self.foreignPolicyProbe = foreignPolicy
    }

    /// Read-only production probe. A read failure is unknown, not clear.
    public static func observeNativeGlobalPolicy() -> ForeignPolicyObservation {
        do {
            return try NativeHelperEnvironment.globalSleepDisabled() ? .conflicted : .clear
        } catch {
            return .unreadable
        }
    }

    public static func nativeCandidate(maximumSessionSeconds: Int = 24) -> LidOnlyLeaseMechanism {
        LidOnlyLeaseMechanism(maximumSessionSeconds: maximumSessionSeconds,
                              make: LidSpecificMechanism.nativeCandidate,
                              baselineAllowsLidSleep: NativeHelperEnvironment.lidOnlyBaselineAllowsAdmission)
    }

    public func admissionAllowed() throws -> Bool {
        guard control == nil else { return false }
        // Effective policy is a conservative admission condition, never ownership of the bit.
        return try baselineAllowsLidSleep()
    }

    public func apply(remainingNanos: UInt64, episodeID: UUID) throws {
        guard control == nil else { throw LidSpecificFailure.lidAlreadyAttempted }
        let native = try make()
        control = native
        let (assertionBudget, overflow) = remainingNanos.addingReportingOverflow(6_000_000_000)
        guard !overflow, assertionBudget <= 30_000_000_000 else {
            throw NativePowerBoundaryFailure.invalidDuration
        }
        // Leave five seconds between the helper lease deadline and the floored OS assertion timeout.
        try native.acquireIdle(remainingNanos: assertionBudget, episodeID: episodeID)
        let receipt = try native.suppressLidAfterJournalCommit()
        guard receipt.allCallsSucceeded else { throw PowerServiceFailure.backend }
    }

    public func prepareRenewal(remainingNanos: UInt64, episodeID: UUID) throws {
        guard let control else { throw LidSpecificFailure.idleNotReady }
        let (assertionBudget, overflow) = remainingNanos.addingReportingOverflow(6_000_000_000)
        guard !overflow, assertionBudget <= 30_000_000_000 else {
            throw NativePowerBoundaryFailure.invalidDuration
        }
        try control.prepareRenewalIdle(remainingNanos: assertionBudget, episodeID: episodeID)
    }

    public func completeRenewal() throws {
        guard let control else { throw LidSpecificFailure.idleNotReady }
        try control.completeRenewalIdle()
    }

    public func readApplied() throws -> Bool? { nil }

    public func readForeignPolicy() throws -> ForeignPolicyObservation {
        do { return try foreignPolicyProbe() }
        catch { return .unreadable }
    }

    public func discardOwnedResourcesAfterFailedApply() throws {
        guard !applyAcknowledged else { throw PowerServiceFailure.backend }
        if let control { _ = try control.releaseOwnedIdle() }
    }

    public func releaseOwnedResourcesAfterFailedRestore() {
        control?.releaseOwnedIdleBestEffort()
    }

    public func clear() throws -> CleanupEvidence {
        guard let control else { throw LidSpecificFailure.idleNotReady }
        // No public readback or successful idle release can prove the separate lid bit cleared.
        let receipt = try control.clearLidAfterJournalCommit()
        let idleCode = try control.releaseOwnedIdle()
        guard receipt.allCallsSucceeded, idleCode == 0 else { throw PowerServiceFailure.backend }
        return .callsAcknowledgedOnly
    }
}
