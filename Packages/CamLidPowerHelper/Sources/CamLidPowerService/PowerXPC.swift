import Foundation
import Security

/// All controller, journal and PM calls are serialized here; no XPC callback runs them directly.
public final class PowerHelperRuntime: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.camlid.power-helper.controller")
    private let service: PowerLeaseService
    private var timer: DispatchSourceTimer?

    public init(service: PowerLeaseService) { self.service = service }

    public func start() {
        queue.async { [self] in
            service.start()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 1, repeating: 1)
            source.setEventHandler { [weak self] in self?.service.poll() }
            timer = source
            source.resume()
        }
    }

    func perform(_ data: Data, owner: UUID, uid: UInt32, reply: @escaping @Sendable (Data) -> Void) {
        queue.async { [self] in
            let response: PowerReply
            if data.count <= 4096, let request = try? JSONDecoder().decode(PowerRequest.self, from: data) {
                response = service.handle(request, owner: owner, uid: uid)
            } else {
                let observed = service.handle(PowerRequest(operation: .inspect), owner: owner, uid: uid)
                response = PowerReply(accepted: false, state: observed.state, reason: "invalidRequest",
                                      mutationAttempted: observed.mutationAttempted)
            }
            // All reply fields are bounded local values, not subprocess output or agent content.
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }

    func disconnected(owner: UUID) {
        queue.async { [self] in service.disconnected(owner: owner) }
    }

    public func observeSystemEvent(reason: String) {
        queue.async { [self] in service.observeSystemEvent(reason: reason) }
    }

    public func shutdown(completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            service.shutdown()
            completion()
        }
    }
}

private final class PowerHelperEndpoint: NSObject, PowerHelperXPC, @unchecked Sendable {
    let owner = UUID()
    private let uid: UInt32
    private let runtime: PowerHelperRuntime
    init(uid: UInt32, runtime: PowerHelperRuntime) { self.uid = uid; self.runtime = runtime }
    func perform(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        runtime.perform(data, owner: owner, uid: uid, reply: reply)
    }
}

public final class PowerHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let runtime: PowerHelperRuntime
    private let peerRequirement: String

    public init(runtime: PowerHelperRuntime, peerRequirement: String) {
        self.runtime = runtime
        self.peerRequirement = peerRequirement
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier > 0 else { return false }
        connection.setCodeSigningRequirement(peerRequirement)
        let endpoint = PowerHelperEndpoint(uid: connection.effectiveUserIdentifier, runtime: runtime)
        connection.exportedInterface = NSXPCInterface(with: PowerHelperXPC.self)
        connection.exportedObject = endpoint
        let owner = endpoint.owner
        let runtime = runtime
        connection.invalidationHandler = { runtime.disconnected(owner: owner) }
        connection.interruptionHandler = { runtime.disconnected(owner: owner) }
        connection.activate()
        return true
    }
}

/// Signed-app transport only. Creating this object does not install a helper or acquire a lease.
public final class PowerHelperClient: @unchecked Sendable {
    private let connection: NSXPCConnection

    public init() throws {
        let requirement = try PowerHelperIdentity.peerRequirement(forHelper: true)
        connection = NSXPCConnection(machServiceName: PowerHelperIdentity.serviceName, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperXPC.self)
        connection.activate()
    }

    public func perform(_ request: PowerRequest, completion: @escaping @Sendable (Result<PowerReply, Error>) -> Void) {
        let once = ReplyOnce(completion)
        guard let data = try? JSONEncoder().encode(request), data.count <= 4096 else {
            once.finish(.failure(PowerServiceFailure.invalidRequest))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
            if once.finish(.failure(PMSetFailure.timeout)) { connection.invalidate() }
        }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in once.finish(.failure(error)) }) as? PowerHelperXPC else {
            once.finish(.failure(PowerServiceFailure.backend))
            return
        }
        proxy.perform(data) { [self] result in
            guard connection.effectiveUserIdentifier == 0, result.count <= 4096,
                  let reply = try? JSONDecoder().decode(PowerReply.self, from: result) else {
                once.finish(.failure(PowerServiceFailure.backend))
                return
            }
            once.finish(.success(reply))
        }
    }

    public func invalidate() { connection.invalidate() }
    deinit { connection.invalidate() }
}

private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<PowerReply, Error>) -> Void)?
    init(_ completion: @escaping @Sendable (Result<PowerReply, Error>) -> Void) { self.completion = completion }
    @discardableResult func finish(_ result: Result<PowerReply, Error>) -> Bool {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(result)
        return callback != nil
    }
}
