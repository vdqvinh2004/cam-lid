import Foundation
import Security
import Testing
import LidRecoveryJournal
@testable import CamLidPowerService

private final class EmptyStore: PowerIntentStore {
    func load() throws -> JournalEntry? { nil }
    func commit(_ entry: JournalEntry, replacing revision: UInt64?) throws { throw PowerServiceFailure.journal }
}

private final class InertBackend: SleepOverrideBackend {
    func readDisabled() throws -> Bool { false }
    func setDisabled(_ disabled: Bool) throws { throw PowerServiceFailure.backend }
}

private final class ResponseOnce: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func finish(_ data: Data?) {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: data)
    }
}

private func request(_ connection: NSXPCConnection, data: Data) async -> Data? {
    await withCheckedContinuation { continuation in
        let response = ResponseOnce(continuation)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { response.finish(nil) }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in response.finish(nil) } as? PowerHelperXPC
        proxy?.perform(data) { response.finish($0) }
    }
}

private func currentHostRequirement() throws -> String {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { throw HelperIdentityFailure.unsigned }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { throw HelperIdentityFailure.unsigned }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data else {
        throw HelperIdentityFailure.unsigned
    }
    // Trusted fixture identity only. Production uses Team ID or root-installed role-separated pins.
    return "cdhash H\"\(hash.map { String(format: "%02x", $0) }.joined())\""
}

@Suite struct XPCTransportTests {
    @Test func exactSignedHostCanQueryButMismatchedIdentityCannot() async throws {
        let service = PowerLeaseService(backend: InertBackend(), store: EmptyStore(), bootID: "fixture",
            clock: { 100 }, safety: { throw PowerServiceFailure.unsafe })
        let runtime = PowerHelperRuntime(service: service)
        runtime.start()
        let requirement = try currentHostRequirement()
        let delegate = PowerHelperListenerDelegate(runtime: runtime, peerRequirement: requirement)
        let listener = NSXPCListener.anonymous()
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = delegate
        listener.activate()
        let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: PowerHelperXPC.self)
        client.setCodeSigningRequirement(requirement)
        client.activate()
        let data = try JSONEncoder().encode(PowerRequest(operation: .inspect))
        let result = try #require(await request(client, data: data))
        let reply = try JSONDecoder().decode(PowerReply.self, from: result)
        #expect(reply.accepted && reply.state == "ready")
        #expect(!reply.mutationAttempted)
        client.invalidate()
        listener.invalidate()

        let denied = NSXPCListener.anonymous()
        denied.setConnectionCodeSigningRequirement("identifier \"com.camlid.deliberately-not-this-test-host\"")
        denied.delegate = delegate
        denied.activate()
        let wrong = NSXPCConnection(listenerEndpoint: denied.endpoint)
        wrong.remoteObjectInterface = NSXPCInterface(with: PowerHelperXPC.self)
        wrong.activate()
        #expect(await request(wrong, data: data) == nil)
        wrong.invalidate()
        denied.invalidate()
        await withCheckedContinuation { continuation in runtime.shutdown { continuation.resume() } }
        withExtendedLifetime(delegate) {}
    }
}
