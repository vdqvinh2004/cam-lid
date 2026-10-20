import Foundation
import CamLidCore

/// Typed IPC client for the `camlid` CLI (T005 CLI half).
///
/// Same-user note: the CLI talks to the running app over a local-only channel
/// (no TCP listener). The `LocalToken` is an opaque in-memory credential: it is
/// compared, never printed, logged, or transmitted off-host. Peer UID/session
/// authentication is enforced by the channel implementation; this client only
/// frames allowlisted commands and enforces the 64 KiB payload bound before
/// anything reaches the transport.
public struct CLIClient: Sendable {
    public let channel: any IPCChannel
    public let token: LocalToken

    public init(channel: any IPCChannel, token: LocalToken) {
        self.channel = channel
        self.token = token
    }

    /// Generic invoke. Wraps the payload in `BoundedPayload` (64 KiB bound) and
    /// maps transport failures to `IPCError`.
    public func invoke(_ command: AllowlistedCommand, payload: Data = Data()) throws(IPCError) -> Data {
        let bounded = try BoundedPayload(payload)
        do {
            return try channel.send(command: command, payload: bounded.bytes)
        } catch let error as IPCError {
            throw error
        } catch {
            // Same-user local channel: any non-protocol transport failure means
            // the app endpoint is not reachable. Never fabricate a reply.
            throw IPCError.unavailable
        }
    }

    // Typed wrappers, one per allowlisted command. All enforce the bound.
    public func status(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.status, payload: payload) }
    public func agentsList(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.agentsList, payload: payload) }
    public func configGet(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.configGet, payload: payload) }
    public func configValidate(_ payload: Data) throws(IPCError) -> Data { try invoke(.configValidate, payload: payload) }
    public func configSet(_ payload: Data) throws(IPCError) -> Data { try invoke(.configSet, payload: payload) }
    public func start(_ payload: Data) throws(IPCError) -> Data { try invoke(.start, payload: payload) }
    public func quit(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.quit, payload: payload) }
    public func stop(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.stop, payload: payload) }
    public func logsExport(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.logsExport, payload: payload) }
    public func recover(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.recover, payload: payload) }
    public func doctor(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.doctor, payload: payload) }
    public func simulate(_ payload: Data) throws(IPCError) -> Data { try invoke(.simulate, payload: payload) }
    public func event(_ payload: Data) throws(IPCError) -> Data { try invoke(.event, payload: payload) }
    public func run(_ payload: Data = Data()) throws(IPCError) -> Data { try invoke(.run, payload: payload) }
}
