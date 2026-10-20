import Foundation
import Testing
@testable import CamLidCore

@Suite("Real same-user transport")
struct LocalControlTests {
    @Test func roundTripAndStoppedEndpoint() throws {
        let directory = URL(fileURLWithPath: "/tmp/cl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = LocalControlServer(directory: directory)
        try server.start { command, data in
            #expect(command == .status)
            return data
        }
        let channel = LocalControlChannel(directory: directory)
        defer { server.stop() }
        #expect(try channel.send(command: .status, payload: Data("test".utf8)) == Data("test".utf8))
        let duplicate = LocalControlServer(directory: directory)
        #expect(throws: (any Error).self) { try duplicate.start { _, _ in Data() } }
        #expect(try channel.send(command: .status, payload: Data()).isEmpty)
        #expect(throws: (any Error).self) { try channel.send(command: .status, payload: Data(repeating: 0, count: 65_537)) }
        server.stop()
        #expect(throws: (any Error).self) { try channel.send(command: .status, payload: Data()) }
    }
    @Test func insecureDirectoryRejected() throws {
        let directory = URL(fileURLWithPath: "/tmp/cl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = LocalControlServer(directory: directory)
        #expect(throws: (any Error).self) { try server.start { _, _ in Data() } }
    }
}

@Suite("Runtime event ingestion")
struct RuntimeAgentTests {
    func event(_ sequence: Int, state: TaskState = .working) throws -> Data {
        try JSONEncoder().encode(NormalizedEvent(provider: "codex", sessionID: "session", runID: "run",
            state: state, evidenceKind: .lifecycle, confidence: .exact, sequence: sequence, receivedMonotonic: 99_999))
    }
    @Test func staleActivityAnchorsToServerReceipt() throws {
        var store = RuntimeAgentStore()
        #expect(try store.ingest(event(0), now: 10) == "applied")
        #expect(store.tasks(now: 20).first?.state == .working)
        #expect(store.tasks(now: 26).first?.state == .unknown)
        #expect(store.tasks(now: 200).first?.unknownUntilMonotonic == 145)
        #expect(try store.ingest(event(0), now: 100) == "duplicate")
        #expect(store.tasks(now: 200).first?.unknownUntilMonotonic == 145)
        #expect(try store.ingest(event(1, state: .completed), now: 201) == "applied")
        #expect(throws: (any Error).self) { try store.ingest(event(2), now: 202) }
    }
    @Test func configuredWaitUsesFirstTransition() throws {
        var store = RuntimeAgentStore()
        store.configure(waitRetentionSeconds: 0)
        _ = try store.ingest(event(0), now: 1)
        _ = try store.ingest(event(1, state: .waiting), now: 10)
        store.configure(waitRetentionSeconds: 0)
        #expect(store.tasks(now: 20).first?.waitUntilMonotonic == 10)
        store.configure(waitRetentionSeconds: 60)
        _ = try store.ingest(event(2, state: .waiting), now: 50)
        #expect(store.tasks(now: 60).first?.waitUntilMonotonic == 10)
        _ = try store.ingest(event(3, state: .working), now: 65)
        _ = try store.ingest(event(4, state: .waiting), now: 70)
        #expect(store.tasks(now: 71).first?.waitUntilMonotonic == 130)
        store.remove(provider: "codex")
        #expect(store.tasks(now: 60).isEmpty)
    }
    @Test func contentFieldsRejected() throws {
        var store = RuntimeAgentStore()
        var object = try JSONSerialization.jsonObject(with: event(0)) as! [String: Any]
        object["prompt"] = "must not be accepted"
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try store.ingest(data, now: 10) }
        #expect(store.tasks(now: 10).isEmpty)
    }
}
