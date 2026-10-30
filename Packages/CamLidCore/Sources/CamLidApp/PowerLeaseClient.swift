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
        guard let data = try? JSONEncoder().encode(Self.request(for: action)),
              let connection = currentConnection() else { return nil }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                self?.drop(connection)
                once.resume(nil)
            } as? any PowerHelperXPC
            guard let proxy else { once.resume(nil); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.replyTimeoutSeconds) {
                self.drop(connection)
                once.resume(nil)
            }
            proxy.perform(data) { reply in once.resume(Self.holdReply(from: reply)) }
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
        case .acquire(let seconds): PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: seconds)
        case .renew(let token, let sequence): PowerRequest(operation: .renew, token: token, sequence: sequence)
        case .release(let token): PowerRequest(operation: .release, token: token)
        }
    }

    static func holdReply(from data: Data) -> HoldReply? {
        guard data.count <= 4096, let reply = try? JSONDecoder().decode(PowerReply.self, from: data) else { return nil }
        return HoldReply(accepted: reply.accepted, state: reply.state, reason: reply.reason, token: reply.token)
    }

    /// Resumes exactly once; a late reply or error after a timeout is ignored.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<HoldReply?, Never>?
        init(_ continuation: CheckedContinuation<HoldReply?, Never>) { self.continuation = continuation }
        func resume(_ value: HoldReply?) {
            lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
            pending?.resume(returning: value)
        }
    }
}
