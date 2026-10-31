import Foundation
import CamLidCore
import CamLidPowerWire

/// XPC client for the closed-lid helper. It keeps one connection for the lifetime of a lease because the helper
/// binds the lease to that connection and restores when it drops. The helper's code signature is pinned through
/// `PowerHelperIdentity`; an unverifiable helper is treated as unreachable, never trusted.
public final class XPCPowerHoldTransport: PowerHoldTransport, @unchecked Sendable {
    public static let replyTimeoutSeconds = 5.0

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let requirement: @Sendable () throws -> String

    public init(requirement: @escaping @Sendable () throws -> String = { try PowerHelperIdentity.peerRequirement(forHelper: true) }) {
        self.requirement = requirement
    }

    public func send(_ action: HoldAction) async -> HoldReply? {
        await exchange(Self.request(for: action))
    }

    /// Read-only state query; never changes the sleep setting.
    public func inspect() async -> HoldReply? {
        await exchange(PowerRequest(operation: .inspect))
    }

    private func exchange(_ request: PowerRequest) async -> HoldReply? {
        guard let data = try? JSONEncoder().encode(request),
              let connection = currentConnection() else { return nil }
        return await withCheckedContinuation { continuation in
            let once = ReplyOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                if once.resume(nil) { self?.drop(connection) }
            } as? any PowerHelperXPC
            guard let proxy else { _ = once.resume(nil); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.replyTimeoutSeconds) { [weak self] in
                // Only a call still waiting means the helper is hung; a completed call must leave the shared
                // connection alone, because dropping it makes the helper restore the sleep setting.
                if once.resume(nil) { self?.drop(connection) }
            }
            proxy.perform(data) { reply in _ = once.resume(Self.holdReply(from: reply)) }
        }
    }

    public func close() {
        lock.lock(); let current = connection; connection = nil; lock.unlock()
        current?.invalidate()
    }

    private func currentConnection() -> NSXPCConnection? {
        lock.lock(); defer { lock.unlock() }
        if let connection { return connection }
        guard let text = try? requirement() else { return nil }
        let made = NSXPCConnection(machServiceName: PowerHelperIdentity.serviceName, options: .privileged)
        made.remoteObjectInterface = NSXPCInterface(with: PowerHelperXPC.self)
        made.setCodeSigningRequirement(text)
        made.invalidationHandler = { [weak self, weak made] in if let made { self?.drop(made) } }
        made.interruptionHandler = { [weak self, weak made] in if let made { self?.drop(made) } }
        made.resume()
        connection = made
        return made
    }

    private func drop(_ dead: NSXPCConnection) {
        lock.lock()
        let wasCurrent = connection === dead
        if wasCurrent { connection = nil }
        lock.unlock()
        if wasCurrent { dead.invalidate() }
    }

    static func request(for action: HoldAction) -> PowerRequest {
        switch action {
        case .acquire(let seconds, let strict):
            PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: seconds, mechanism: strict ? .strict : nil)
        case .renew(let token, let sequence): PowerRequest(operation: .renew, token: token, sequence: sequence)
        case .release(let token): PowerRequest(operation: .release, token: token)
        }
    }

    static func holdReply(from data: Data) -> HoldReply? {
        guard data.count <= 4096, let reply = try? JSONDecoder().decode(PowerReply.self, from: data) else { return nil }
        return HoldReply(accepted: reply.accepted, state: reply.state, reason: reply.reason, token: reply.token)
    }

    /// Resumes exactly once; a late reply or error after a timeout is ignored. `resume` reports whether this
    /// call was the one that completed the exchange.
    final class ReplyOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<HoldReply?, Never>?
        init(_ continuation: CheckedContinuation<HoldReply?, Never>) { self.continuation = continuation }
        @discardableResult func resume(_ value: HoldReply?) -> Bool {
            lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
            pending?.resume(returning: value)
            return pending != nil
        }
    }
}
