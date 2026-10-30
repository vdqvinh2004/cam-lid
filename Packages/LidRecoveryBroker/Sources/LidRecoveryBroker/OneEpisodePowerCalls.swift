import Foundation

// Experimental system boundary only, never supplied through IPC.
@_spi(TestInputs)
public enum EpisodeSafetyStage: Sendable { case beforeEnable, monitoring }

@_spi(TestInputs)
public protocol EpisodeSafetySource: Sendable {
    func allows(_ clock: BrokerClockSnapshot, stage: EpisodeSafetyStage) -> Bool
}

@_spi(TestInputs)
public enum EpisodeExecutionMode: String, Codable, Sendable { case simulated, nativeSDK }

@_spi(TestInputs)
public enum EpisodeLidCallResult: Codable, Equatable, Sendable {
    case notDispatched(stage: String, code: Int32?, serviceReleaseCode: Int32?)
    case returned(selectorCode: Int32, serviceReleaseCode: Int32, connectionCloseCode: Int32)

    public var successfulSelectorReturn: Bool {
        if case .returned(let code, _, _) = self { return code == 0 }
        return false
    }
    public var selectorWasDispatched: Bool {
        if case .returned = self { return true }
        return false
    }
}

@_spi(TestInputs)
public protocol EpisodeIdleAssertion: Sendable {
    // A returned release code is an observation, never a physical-restoration claim.
    func release() throws -> Int32
}

@_spi(TestInputs)
public protocol OneEpisodePowerCalls: Sendable {
    var executionMode: EpisodeExecutionMode { get }
    func acquire(remaining: UInt64) throws -> any EpisodeIdleAssertion
    func setLid(enabled: Bool) throws -> EpisodeLidCallResult
}
