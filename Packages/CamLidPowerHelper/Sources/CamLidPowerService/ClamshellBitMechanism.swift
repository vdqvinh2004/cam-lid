import Foundation
import IOKit
import IOKit.pwr_mgt

/// The OS calls Strict needs, injected so tests never touch power state.
public struct ClamshellBitCalls: Sendable {
    /// Sets or clears the root-domain clamshell-sleep-disable bit (selector `kPMSetClamshellSleepState`).
    public var setBit: @Sendable (Bool) -> Int32
    /// `setBit` returns this when `IOPMrootDomain` does not exist (shutdown teardown, or before it registers): the
    /// bit lives in that object, so there is nothing to clear and a restart would clear it anyway.
    public static let rootDomainMissing: Int32 = -1
    /// Creates a `PreventUserIdleSystemSleep` assertion the OS releases after `seconds`.
    public var createIdleAssertion: @Sendable (_ seconds: Double) -> (code: Int32, id: UInt32)
    /// Restarts the assertion's timeout from now.
    public var setTimeout: @Sendable (_ id: UInt32, _ seconds: Double) -> Int32
    public var release: @Sendable (_ id: UInt32) -> Int32

    public init(setBit: @escaping @Sendable (Bool) -> Int32,
                createIdleAssertion: @escaping @Sendable (Double) -> (code: Int32, id: UInt32),
                setTimeout: @escaping @Sendable (UInt32, Double) -> Int32,
                release: @escaping @Sendable (UInt32) -> Int32) {
        self.setBit = setBit; self.createIdleAssertion = createIdleAssertion
        self.setTimeout = setTimeout; self.release = release
    }

    public static let native = ClamshellBitCalls(
        setBit: { on in
            let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            guard root != 0 else { return rootDomainMissing }
            defer { IOObjectRelease(root) }
            var connect: io_connect_t = 0
            let opened = IOServiceOpen(root, mach_task_self_, 0, &connect)
            guard opened == KERN_SUCCESS else { return opened }
            defer { IOServiceClose(connect) }
            var input: UInt64 = on ? 1 : 0
            return IOConnectCallScalarMethod(connect, UInt32(kPMSetClamshellSleepState), &input, 1, nil, nil)
        },
        createIdleAssertion: { seconds in
            var id: IOPMAssertionID = 0
            let properties: [String: Any] = [
                kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleSystemSleep,
                kIOPMAssertionNameKey: "CamLid Strict closed lid",
                kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
                kIOPMAssertionTimeoutKey: seconds,
                kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease]
            let code = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
            return (code, id)
        },
        setTimeout: { id, seconds in
            IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutKey as CFString, seconds as CFNumber)
        },
        release: { id in IOPMAssertionRelease(id) })
}

/// Strict (ADR 0003): disables only lid-close sleep through the kernel clamshell bit, and covers idle sleep with an
/// assertion the OS releases by itself. The bit is shared with powerd, has no owner and no getter, outlives this
/// process and is cleared by a restart; clearing it with the lid closed sleeps the Mac (experiments E1-E6).
public final class ClamshellBitMechanism: LeasePowerMechanism {
    public static let familyName = "clamshell-bit-v1"
    /// The OS releases the idle assertion this long after the lease deadline when nobody renews it.
    static let assertionMarginSeconds = 6.0
    public let family = familyName
    public let maximumSessionSeconds = PowerLeaseService.maximumSessionSeconds
    public let restartClearsPolicy = true
    public let acknowledgedClearIsRestore = true
    public private(set) var applyAcknowledged = false
    private let calls: ClamshellBitCalls
    private let foreignPolicy: () throws -> ForeignPolicyObservation
    private var assertion: UInt32?

    public init(calls: ClamshellBitCalls = .native,
                foreignPolicy: @escaping () throws -> ForeignPolicyObservation = LidOnlyLeaseMechanism.observeNativeGlobalPolicy) {
        self.calls = calls
        self.foreignPolicy = foreignPolicy
    }

    /// Another app's `SleepDisabled` already keeps the Mac awake; Strict leaves it alone, as Standard does.
    public func admissionAllowed() throws -> Bool { try foreignPolicy() == .clear }

    public func apply(remainingNanos: UInt64, episodeID: UUID) throws {
        applyAcknowledged = false
        guard assertion == nil else { throw PowerServiceFailure.backend }
        // The assertion first: if setting the bit fails, nothing outlives this process.
        let created = calls.createIdleAssertion(Self.seconds(remainingNanos))
        guard created.code == 0 else { throw PowerServiceFailure.backend }
        assertion = created.id
        guard calls.setBit(true) == 0 else { throw PowerServiceFailure.backend }
        applyAcknowledged = true
    }

    /// Re-sets the bit at every renewal: powerd may have cleared the shared bit while the lid was open.
    public func prepareRenewal(remainingNanos: UInt64, episodeID: UUID) throws {
        guard let assertion else { throw PowerServiceFailure.backend }
        guard calls.setTimeout(assertion, Self.seconds(remainingNanos)) == 0, calls.setBit(true) == 0 else {
            throw PowerServiceFailure.backend
        }
    }

    public func readApplied() throws -> Bool? { nil }

    public func readForeignPolicy() throws -> ForeignPolicyObservation {
        do { return try foreignPolicy() } catch { return .unreadable }
    }

    /// Unconditional and idempotent; also run by the recovery job, which owns no assertion.
    public func clear() throws -> CleanupEvidence {
        let bit = calls.setBit(false)
        let idle = assertion.map(calls.release) ?? 0
        assertion = nil
        applyAcknowledged = false
        // No root domain means no bit to leave set: the helper being stopped by a shutdown is not a failed restore.
        guard bit == 0 || bit == ClamshellBitCalls.rootDomainMissing, idle == 0 else { throw PowerServiceFailure.backend }
        return .callsAcknowledgedOnly
    }

    public func discardOwnedResourcesAfterFailedApply() throws {
        _ = calls.setBit(false)
        if let assertion { _ = calls.release(assertion) }
        assertion = nil
        applyAcknowledged = false
    }

    public func releaseOwnedResourcesAfterFailedRestore() {
        if let assertion { _ = calls.release(assertion) }
        assertion = nil
    }

    private static func seconds(_ nanos: UInt64) -> Double { Double(nanos) / 1_000_000_000 + assertionMarginSeconds }
}
