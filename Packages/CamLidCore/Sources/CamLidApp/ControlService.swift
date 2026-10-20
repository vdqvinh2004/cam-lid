import Foundation
import CamLidCore

/// Same-user check seam for the app-side IPC endpoint. The real implementation
/// compares the peer credential UID against the app's UID; tests inject fakes.
public protocol PeerIdentityChecker: Sendable {
    func isSameUser(peerUID: uid_t) -> Bool
}

/// Recovery ownership as established before any restore attempt.
/// Unknown or conflicting ownership MUST reject: the app never restores a
/// journal it cannot prove it owns.
public enum RecoveryOwnership: String, Sendable {
    case owned
    case unknown
    case conflicting
}

/// App-side IPC service (specs/005-native-ux T005 app half, FR-018 scope).
///
/// Uses the shared contract types from CamLidCore (IPC.swift:
/// AllowlistedCommand, IPCError, IPCChannel, LocalToken) — nothing is
/// redefined here. No TCP listener; same-user local channel only.
///
/// Validation order per request: command allowlist → 64 KiB payload bound →
/// same-user peer check → dispatch. Recovery additionally requires proven
/// ownership via `authorizeRecovery(_:)`.
public struct ControlService: Sendable {
    /// Local mirror of the shared payload bound.
    /// Authority: CamLidCore.PolicyLimits.maxEventBytes — keep in sync.
    public static let maxPayloadBytes = 64 * 1_024

    public let channel: any IPCChannel
    public let identityChecker: any PeerIdentityChecker

    public init(channel: any IPCChannel, identityChecker: any PeerIdentityChecker) {
        self.channel = channel
        self.identityChecker = identityChecker
    }

    /// Parses a raw command string against the shared allowlist. Unknown
    /// strings reject as invalid input (never dispatched, never executed).
    public static func command(from rawValue: String) throws(IPCError) -> AllowlistedCommand {
        guard let command = AllowlistedCommand(rawValue: rawValue) else {
            throw .invalidInput("unknownCommand:\(rawValue)")
        }
        return command
    }

    /// Bounded-payload check. Mirrors CamLidCore.BoundedPayload semantics.
    public func validatePayload(_ payload: Data) throws(IPCError) {
        guard payload.count <= Self.maxPayloadBytes else {
            throw .tooLarge(payload.count)
        }
    }

    /// Full request path: allowlist (by type) + bound + same-user + dispatch.
    /// Recovery commands additionally require `authorizeRecovery(_:)` first;
    /// this method does NOT grant recovery by itself.
    public func request(_ command: AllowlistedCommand, payload: Data, peerUID: uid_t) throws -> Data {
        if command == .recover {
            throw IPCError.policyDenied("recoveryRequiresOwnershipProof")
        }
        try validatePayload(payload)
        guard identityChecker.isSameUser(peerUID: peerUID) else {
            throw IPCError.unauthorized
        }
        return try channel.send(command: command, payload: payload)
    }

    /// Unknown-ownership rejection: only `.owned` proceeds. `.unknown` and
    /// `.conflicting` throw and the caller surfaces recovery-required UI.
    public func authorizeRecovery(_ ownership: RecoveryOwnership) throws(IPCError) {
        switch ownership {
        case .owned:
            return
        case .unknown:
            throw .unauthorized
        case .conflicting:
            throw .recoveryRequired
        }
    }
}
