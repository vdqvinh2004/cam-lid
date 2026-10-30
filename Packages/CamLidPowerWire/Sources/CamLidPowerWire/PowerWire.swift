import Foundation

public struct PowerRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case inspect, acquire, renew, release }
    public var version = 1
    public let operation: Operation
    public var token: UUID?
    public var sequence: UInt64?
    public var sessionSeconds: Int?

    public init(operation: Operation, token: UUID? = nil, sequence: UInt64? = nil,
                sessionSeconds: Int? = nil) {
        self.operation = operation
        self.token = token
        self.sequence = sequence
        self.sessionSeconds = sessionSeconds
    }
}

public struct PowerReply: Codable, Sendable {
    public let accepted: Bool
    public let state: String
    public let reason: String
    public let token: UUID?
    public let leaseRemainingSeconds: Double?
    public let sessionRemainingSeconds: Double?
    public let mutationAttempted: Bool
    public let mechanismFamily: String?
    // This implementation is a competitor-style candidate, never qualification evidence.
    public private(set) var qualifiedClosedLidProtection = false

    public init(accepted: Bool, state: String, reason: String, token: UUID? = nil,
                leaseRemainingSeconds: Double? = nil, sessionRemainingSeconds: Double? = nil,
                mutationAttempted: Bool = false, mechanismFamily: String? = nil) {
        self.accepted = accepted
        self.state = state
        self.reason = reason
        self.token = token
        self.leaseRemainingSeconds = leaseRemainingSeconds
        self.sessionRemainingSeconds = sessionRemainingSeconds
        self.mutationAttempted = mutationAttempted
        self.mechanismFamily = mechanismFamily
    }
}
