import Foundation

/// Shared IPC contract. GUI and CLI use this channel; no TCP listener.
/// T005 (shared half): allowlisted commands, 64 KiB payload bound, local token.
public enum AllowlistedCommand: String, Sendable, Codable, CaseIterable {
    case status
    case agentsList
    case configGet
    case configValidate
    case configSet
    case start
    case stop
    case quit
    case logsExport
    case recover
    case doctor
    case simulate
    case event
    case agentDiagnostic
    case run
    case diagnose
    case admitCommand, renewCommand, finishCommand
    case sleep
}

public enum IPCError: Error, Equatable, Sendable {
    case unavailable
    /// The app is running but every worker slot is taken; retrying shortly succeeds.
    case busy
    case unauthorized
    case invalidInput(String)
    case policyDenied(String)
    case recoveryRequired
    case tooLarge(Int)
}

/// Payload envelope enforcing the 64 KiB event bound (domain-model.md).
public struct BoundedPayload: Sendable, Equatable {
    public let bytes: Data
    public init(_ bytes: Data) throws(IPCError) {
        guard bytes.count <= PolicyLimits.maxEventBytes else {
            throw .tooLarge(bytes.count)
        }
        self.bytes = bytes
    }
}

/// Same-user local channel. Implementations authenticate the peer UID/session;
/// the token never leaves the host.
public protocol IPCChannel: Sendable {
    func send(command: AllowlistedCommand, payload: Data) throws -> Data
}

/// Local-only connection token. Opaque; compared, never printed or transmitted.
public struct LocalToken: Sendable, Equatable {
    public let high: UInt64
    public let low: UInt64
    public static func generate() -> LocalToken {
        LocalToken(high: .random(in: .min ... .max), low: .random(in: .min ... .max))
    }
}
