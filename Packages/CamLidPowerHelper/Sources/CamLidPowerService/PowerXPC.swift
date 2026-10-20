import Foundation
import Security

@objc public protocol PowerHelperXPC {
    func perform(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}

public enum HelperIdentityFailure: Error { case unsigned, invalidIdentity, invalidRequirement, teamUnavailable }

public enum PowerHelperIdentity {
    public static let serviceName = "com.camlid.power-helper"
    public static let appIdentifier = "com.camlid.CamLid"
    public static let qaIdentifier = "com.camlid.PowerCandidate"

    private static func signingInformation(expectedIdentifier: String) throws -> [String: Any] {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw HelperIdentityFailure.unsigned
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw HelperIdentityFailure.invalidIdentity
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == expectedIdentifier,
              let flags = values[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & SecCodeSignatureFlags.runtime.rawValue != 0 else {
            throw HelperIdentityFailure.invalidIdentity
        }
        let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        guard entitlements?["com.apple.security.get-task-allow"] as? Bool != true else {
            throw HelperIdentityFailure.invalidIdentity
        }
        return values
    }

    /// Production identity comes from our validated executable, never from IPC input.
    public static func ownTeam(expectedIdentifier: String) throws -> String {
        let values = try signingInformation(expectedIdentifier: expectedIdentifier)
        guard let team = values[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw HelperIdentityFailure.teamUnavailable
        }
        guard team.count == 10, team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
            throw HelperIdentityFailure.invalidIdentity
        }
        return team
    }

    public static func peerRequirement(forHelper: Bool) throws -> String {
        if forHelper, Bundle.main.bundleIdentifier == qaIdentifier {
            return try localPeerRequirement(forHelper: true, ownIdentifier: qaIdentifier)
        }
        let ownIdentifier = forHelper ? appIdentifier : serviceName
        do {
            let team = try ownTeam(expectedIdentifier: ownIdentifier)
            return try requirement(identifier: forHelper ? serviceName : appIdentifier, team: team)
        } catch HelperIdentityFailure.teamUnavailable {
            return try localPeerRequirement(forHelper: forHelper, ownIdentifier: ownIdentifier)
        }
    }

    private static func localPeerRequirement(forHelper: Bool, ownIdentifier: String) throws -> String {
        // Root-installed exact pins, never caller-configured trust or a UID-only bypass.
        let pins = try LocalIdentityPins.loadInstalled()
        let values = try signingInformation(expectedIdentifier: ownIdentifier)
        guard let hash = values[kSecCodeInfoUnique as String] as? Data, hash.count == 20 else {
            throw HelperIdentityFailure.invalidIdentity
        }
        let actual = hash.map { String(format: "%02x", $0) }.joined()
        guard actual == (forHelper ? pins.appCDHash : pins.helperCDHash) else {
            throw HelperIdentityFailure.invalidIdentity
        }
        return try pins.requirement(forHelper: forHelper)
    }

    public static func requirement(identifier: String, team: String) throws -> String {
        guard [appIdentifier, serviceName].contains(identifier), team.count == 10,
              team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
            throw HelperIdentityFailure.invalidRequirement
        }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            throw HelperIdentityFailure.invalidRequirement
        }
        return text
    }
}

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
