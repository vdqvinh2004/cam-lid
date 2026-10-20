import Foundation
import Testing
@testable import CamLidCore

@Suite("Codex exec collaboration refusal")
struct CodexCollaborationTests {
    private func collaboration(_ type: String) -> Data {
        Data("""
            {"type":"\(type)","item":{"id":"item-1","type":"collab_tool_call","tool":"spawn_agent","sender_thread_id":"parent","receiver_thread_ids":["child"],"prompt":"SECRET_PROMPT","agents_states":{"child":{"status":"running","message":"SECRET_CHILD_TEXT"}},"status":"completed"}}
            """.utf8)
    }

    @Test(arguments: ["item.started", "item.updated", "item.completed"])
    func childItemsRefuseInsteadOfSilentlyAllowingParentIdle(_ type: String) throws {
        var adapter = CodexAdapter(optIn: true)
        #expect(adapter.parse(json: collaboration(type), receivedMonotonic: 2) == .ignored(reason: "codexCollaborationUnsupported"))

        var stream = try ProviderStream(provider: "codex", streamID: "collaboration-fixture")
        _ = try stream.consume(Data(#"{"type":"thread.started","thread_id":"parent"}"#.utf8), now: 1)
        let started = try #require(stream.consume(Data(#"{"type":"turn.started"}"#.utf8), now: 1).first)
        #expect(started.state == .working)
        #expect(throws: IPCError.policyDenied("codexCollaborationUnsupported")) {
            try stream.consume(collaboration(type), now: 2)
        }
        // A caller catching the refusal must not resume the same unsafe stream.
        #expect(throws: IPCError.policyDenied("codexCollaborationUnsupported")) {
            try stream.consume(Data(#"{"type":"turn.completed"}"#.utf8), now: 3)
        }
        let lost = try #require(stream.disconnected(now: 4).first)
        #expect(lost.runID == started.runID && lost.state == .unknown)
        let encoded = String(decoding: try JSONEncoder().encode(lost), as: UTF8.self)
        #expect(!encoded.contains("SECRET") && !encoded.contains("child"))
    }

    @Test func ordinaryToolItemDoesNotRefuseOrBecomeCompletion() throws {
        var stream = try ProviderStream(provider: "codex", streamID: "ordinary-fixture")
        _ = try stream.consume(Data(#"{"type":"thread.started","thread_id":"parent"}"#.utf8), now: 1)
        #expect(try stream.consume(Data(#"{"type":"turn.started"}"#.utf8), now: 1).first?.state == .working)
        #expect(try stream.consume(Data(#"{"type":"item.completed","item":{"type":"mcp_tool_call","status":"completed","arguments":{"secret":"not stored"}}}"#.utf8), now: 2).isEmpty)
        #expect(try stream.consume(Data(#"{"type":"turn.completed"}"#.utf8), now: 3).first?.state == .idle)
        #expect(try stream.disconnected(now: 4).isEmpty)
    }

    @Test func collaborationAfterParentIdleInvalidatesThatIdleEvidence() throws {
        var stream = try ProviderStream(provider: "codex", streamID: "late-collaboration")
        _ = try stream.consume(Data(#"{"type":"thread.started","thread_id":"parent"}"#.utf8), now: 1)
        _ = try stream.consume(Data(#"{"type":"turn.started"}"#.utf8), now: 1)
        let idle = try #require(stream.consume(Data(#"{"type":"turn.completed"}"#.utf8), now: 2).first)
        #expect(idle.state == .idle)
        #expect(throws: IPCError.policyDenied("codexCollaborationUnsupported")) {
            try stream.consume(collaboration("item.started"), now: 3)
        }
        let unknown = try #require(stream.disconnected(now: 4).first)
        #expect(unknown.runID == idle.runID && unknown.state == .unknown && unknown.sequence == idle.sequence + 1)
        #expect(try stream.disconnected(now: 5).isEmpty)
    }

    @Test func optOutStillIgnoresCollaboration() {
        var adapter = CodexAdapter()
        #expect(adapter.parse(json: collaboration("item.completed"), receivedMonotonic: 1) == .ignored(reason: "optInDisabled"))
    }
}
