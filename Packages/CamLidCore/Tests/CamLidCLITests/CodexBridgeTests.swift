import Foundation
import Testing
import CamLidCore
import CamLidCLI

private final class CodexBridgeFixtureChannel: IPCChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [NormalizedEvent] = []

    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        guard command == .event else { throw IPCError.policyDenied("unexpectedFixtureCommand") }
        let event = try JSONDecoder().decode(NormalizedEvent.self, from: payload)
        lock.lock(); saved.append(event); lock.unlock()
        return Data(#"{"accepted":true}"#.utf8)
    }

    var events: [NormalizedEvent] {
        lock.lock(); defer { lock.unlock() }; return saved
    }
}

@Suite("Codex collaboration bridge boundary")
struct CodexBridgeTests {
    @Test(arguments: ["item.started", "item.updated", "item.completed"])
    func unsupportedCollaborationRejectsBeforeParentIdleAndForwardsUnknown(_ type: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-codex-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("authored-fixture.jsonl")
        let input = [#"{"type":"thread.started","thread_id":"fixture-parent"}"#,
                     #"{"type":"turn.started"}"#,
                     """
                     {"type":"\(type)","item":{"type":"collab_tool_call","tool":"spawn_agent","receiver_thread_ids":["PRIVATE_CHILD"],"prompt":"PRIVATE_PROMPT","agents_states":{"PRIVATE_CHILD":{"status":"running","message":"PRIVATE_OUTPUT"}},"status":"completed"}}
                     """,
                     #"{"type":"turn.completed"}"#].joined(separator: "\n") + "\n"
        try Data(input.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let channel = CodexBridgeFixtureChannel()
        let result = ProviderBridge.run(provider: "codex", channel: channel, input: handle)
        #expect(result.exitCode == 4)
        #expect(result.json.contains("bridgeInterruptedOrRejected") && result.json.contains("\"powerActuation\":false"))
        let events = channel.events
        #expect(events.map(\.state) == [.working, .unknown])
        #expect(events.first?.runID == events.last?.runID && events.last?.sequence == 1)
        #expect(!events.contains { $0.state == .idle || $0.state == .completed })
        let forwarded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
        #expect(!forwarded.contains("PRIVATE") && !result.json.contains("PRIVATE"))
        var runtime = RuntimeAgentStore()
        for event in events { _ = try runtime.ingest(JSONEncoder().encode(event), now: event.receivedMonotonic) }
        #expect(runtime.tasks(now: try #require(events.last?.receivedMonotonic)).first?.state == .unknown)
    }
}
