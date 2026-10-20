import Foundation
import Darwin
import IOKit
@_spi(TestInputs) import LidNativeAdapter

public enum LidSpecificFailure: Error, Equatable {
    case rootRequired, idleAlreadyCreated, idleNotReady, lidAlreadyAttempted, clearAlreadyAttempted
    case suppressionNotAcknowledged
}

/// Receipt for an unsupported shared lid-only control, not a resource ownership/readback token.
public enum LidControlReceipt: Equatable, Sendable {
    case notDispatched(stage: String, code: Int32?, serviceReleaseCode: Int32?)
    case returned(selectorCode: Int32, serviceReleaseCode: Int32, connectionCloseCode: Int32)

    public var allCallsSucceeded: Bool {
        if case .returned(0, 0, 0) = self { return true }
        return false
    }
    public var restorationVerified: Bool { false }
}

/// Separate lid-only and idle resources. Deliberately NOT SleepOverrideBackend:
/// a composite registry value cannot implement a getter for the shared selector's bit.
/// The authenticated lease controller/journal must arbitrate and record intent before use.
/// No executable/service selects this candidate yet; existing installed v3 stays unchanged.
public final class LidSpecificMechanism {
    private let assertionCalls: NativePowerSystemCalls
    private let lid: NativeSharedLidBoundary
    private var idle: NativeOwnedIdleAssertion?
    private var pendingReplacement: NativeOwnedIdleAssertion?
    private var releaseUncertain = false
    private var idleCreationAttempted = false
    private var suppressAttempted = false
    public private(set) var suppressionAcknowledged = false
    private var clearAttempted = false
    public let mutatesGlobalSleepDisabled = false
    public let sharedLidControlHasOSOwnedExpiry = false

    @_spi(CandidateInputs)
    public init(assertionCalls: NativePowerSystemCalls, rootCalls: NativeRootDomainSystemCalls) {
        self.assertionCalls = assertionCalls
        lid = NativeSharedLidBoundary(systemCalls: rootCalls)
    }

    /// Creates bindings only; no assertion or selector call until explicit methods below.
    public static func nativeCandidate() throws -> LidSpecificMechanism {
        guard geteuid() == 0 else { throw LidSpecificFailure.rootRequired }
        return LidSpecificMechanism(assertionCalls: .sdkBindings, rootCalls: .sdkBindings)
    }

    public func acquireIdle(remainingNanos: UInt64, episodeID: UUID) throws {
        guard !idleCreationAttempted else { throw LidSpecificFailure.idleAlreadyCreated }
        idleCreationAttempted = true
        idle = try NativeOwnedIdleAssertion(remainingNanos: remainingNanos, episodeID: episodeID,
                                          systemCalls: assertionCalls)
    }

    public func prepareRenewalIdle(remainingNanos: UInt64, episodeID: UUID) throws {
        guard suppressionAcknowledged, !clearAttempted, let idle, idle.releaseState == .notAttempted,
              pendingReplacement == nil else { throw LidSpecificFailure.idleNotReady }
        pendingReplacement = try NativeOwnedIdleAssertion(remainingNanos: remainingNanos, episodeID: episodeID,
                                                        systemCalls: assertionCalls)
    }

    public func completeRenewalIdle() throws {
        guard suppressionAcknowledged, !clearAttempted, let old = idle,
              let replacement = pendingReplacement else { throw LidSpecificFailure.idleNotReady }
        idle = replacement
        pendingReplacement = nil
        do {
            guard try old.release() == 0 else {
                releaseUncertain = true
                throw PowerServiceFailure.backend
            }
        } catch {
            releaseUncertain = true
            throw error
        }
    }

    /// One dispatch attempt. Caller must keep uncertainty if a result is missing/failed.
    public func suppressLidAfterJournalCommit() throws -> LidControlReceipt {
        guard let idle, idle.releaseState == .notAttempted else { throw LidSpecificFailure.idleNotReady }
        guard !suppressAttempted else { throw LidSpecificFailure.lidAlreadyAttempted }
        suppressAttempted = true
        let result = receipt(lid.callUnsupportedSharedSelector(enabled: true))
        if case .returned(selectorCode: 0, serviceReleaseCode: _, connectionCloseCode: _) = result {
            suppressionAcknowledged = true
        }
        return result
    }

    /// No repeat/reset fallback. Does not claim shared-bit ownership or verified restoration.
    public func clearLidAfterJournalCommit() throws -> LidControlReceipt {
        guard suppressionAcknowledged else { throw LidSpecificFailure.suppressionNotAcknowledged }
        guard !clearAttempted else { throw LidSpecificFailure.clearAlreadyAttempted }
        clearAttempted = true
        return receipt(lid.callUnsupportedSharedSelector(enabled: false))
    }

    public func releaseOwnedIdle() throws -> Int32 {
        guard let idle else { throw LidSpecificFailure.idleNotReady }
        let first = try idle.release()
        if first != 0 { releaseUncertain = true }
        if let pending = pendingReplacement, pending.releaseState == .notAttempted {
            pendingReplacement = nil
            let second = try pending.release()
            if second != 0 { releaseUncertain = true; if first == 0 { return second } }
        }
        return releaseUncertain && first == 0 ? kIOReturnError : first
    }

    public func releaseOwnedIdleBestEffort() {
        if let idle, idle.releaseState == .notAttempted {
            if (try? idle.release()) != 0 { releaseUncertain = true }
        }
        if let pending = pendingReplacement, pending.releaseState == .notAttempted {
            pendingReplacement = nil
            if (try? pending.release()) != 0 { releaseUncertain = true }
        }
    }

    private func receipt(_ result: NativeLidCallResult) -> LidControlReceipt {
        switch result {
        case .notDispatched(let stage, let code, let release):
            return .notDispatched(stage: stage, code: code, serviceReleaseCode: release)
        case .returned(let code, let release, let close):
            return .returned(selectorCode: code, serviceReleaseCode: release, connectionCloseCode: close)
        }
    }
}
