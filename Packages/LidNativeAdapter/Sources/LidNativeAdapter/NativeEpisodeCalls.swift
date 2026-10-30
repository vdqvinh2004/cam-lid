import Foundation
@_spi(TestInputs) import LidRecoveryBroker

/// Bridge to fixed controller. Injected functions are trusted test OS boundaries, not IPC options.
@_spi(TestInputs)
public final class NativeEpisodeCalls: OneEpisodePowerCalls, @unchecked Sendable {
    public let executionMode: EpisodeExecutionMode
    private let episodeID: UUID
    private let assertionCalls: NativePowerSystemCalls
    private let lid: NativeSharedLidBoundary

    public convenience init(episodeID: UUID, fakeAssertionCalls: NativePowerSystemCalls,
                            fakeRootCalls: NativeRootDomainSystemCalls) {
        self.init(episodeID: episodeID, assertionCalls: fakeAssertionCalls,
                  rootCalls: fakeRootCalls, mode: .simulated)
    }

    private init(episodeID: UUID, assertionCalls: NativePowerSystemCalls,
                 rootCalls: NativeRootDomainSystemCalls, mode: EpisodeExecutionMode) {
        self.episodeID = episodeID; self.assertionCalls = assertionCalls
        lid = NativeSharedLidBoundary(systemCalls: rootCalls)
        executionMode = mode
    }

    // Defines native code only. No fixture/CLI selects or evaluates this factory.
    public static func sdkBindings(episodeID: UUID) -> NativeEpisodeCalls {
        NativeEpisodeCalls(episodeID: episodeID, assertionCalls: .sdkBindings,
            rootCalls: .sdkBindings, mode: .nativeSDK)
    }

    private final class OwnedAssertion: EpisodeIdleAssertion, @unchecked Sendable {
        private let owned: NativeOwnedIdleAssertion
        init(_ owned: NativeOwnedIdleAssertion) { self.owned = owned }
        func release() throws -> Int32 { try owned.release() }
    }

    public func acquire(remaining: UInt64) throws -> any EpisodeIdleAssertion {
        OwnedAssertion(try NativeOwnedIdleAssertion(remainingNanos: remaining,
            episodeID: episodeID, systemCalls: assertionCalls))
    }

    public func setLid(enabled: Bool) -> EpisodeLidCallResult {
        switch lid.callUnsupportedSharedSelector(enabled: enabled) {
        case .notDispatched(let stage, let code, let released):
            return .notDispatched(stage: stage, code: code, serviceReleaseCode: released)
        case .returned(let code, let released, let closed):
            return .returned(selectorCode: code, serviceReleaseCode: released, connectionCloseCode: closed)
        }
    }
}
