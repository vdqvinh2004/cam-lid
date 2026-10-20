import Testing
import Foundation
@testable import CamLidCore

@Suite("Provider stream lifecycle boundaries")
struct ProviderStreamTests {
    @Test func permissionReplyMustNotBeClassifiedAsNewPermissionRequest() throws {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "stdin")
        let reply = adapter.parse(OpenCodeEventPayload(type: "permission.replied", sessionID: "s", permission: "allow"), receivedMonotonic: 1)
        guard case .event(let event) = reply else { Issue.record("Missing permission reply"); return }
        #expect(event.state == .working)
    }
    @Test func stepsAndDisconnectNeverProveCompletion() throws {
        var stream = try ProviderStream(provider: "opencode", streamID: "test")
        var runtime = RuntimeAgentStore()
        let lines = [#"{"type":"step_start","sessionID":"s"}"#,
                     #"{"type":"step_finish","sessionID":"s","part":{"reason":"tool-calls"}}"#,
                     #"{"type":"step_start","sessionID":"s"}"#]
        for line in lines {
            for event in try stream.consume(Data(line.utf8), now: 1) {
                _ = try runtime.ingest(JSONEncoder().encode(event), now: 1)
            }
        }
        #expect(runtime.tasks(now: 1).first?.state == .working)
        for event in try stream.disconnected(now: 2) { _ = try runtime.ingest(JSONEncoder().encode(event), now: 2) }
        #expect(runtime.tasks(now: 2).first?.state == .unknown)
        #expect(runtime.tasks(now: 2).first?.unknownUntilMonotonic == 122)
    }
    @Test func parallelStreamsAndReusedTurnsAreIsolated() throws {
        var first = try ProviderStream(provider: "codex", streamID: "one")
        var second = try ProviderStream(provider: "codex", streamID: "two")
        var runtime = RuntimeAgentStore()
        for line in [#"{"type":"thread.started","thread_id":"thread"}"#,
                     #"{"type":"turn.started"}"#] {
            for event in try first.consume(Data(line.utf8), now: 1) { _ = try runtime.ingest(JSONEncoder().encode(event), now: 1) }
            for event in try second.consume(Data(line.utf8), now: 1) { _ = try runtime.ingest(JSONEncoder().encode(event), now: 1) }
        }
        for event in try first.consume(Data(#"{"type":"turn.failed"}"#.utf8), now: 2) { _ = try runtime.ingest(JSONEncoder().encode(event), now: 2) }
        #expect(runtime.tasks(now: 2).filter { $0.state == .working }.count == 1)
        for event in try first.consume(Data(#"{"type":"turn.started"}"#.utf8), now: 3) { _ = try runtime.ingest(JSONEncoder().encode(event), now: 3) }
        #expect(runtime.tasks(now: 3).filter { $0.state == .working }.count == 2)
    }
    @Test func malformedAndOversizedStreamsReject() throws {
        var stream = try ProviderStream(provider: "codex")
        #expect(throws: (any Error).self) { try stream.consume(Data("{truncated".utf8), now: 1) }
        #expect(throws: (any Error).self) { try stream.consume(Data(repeating: 1, count: 65_537), now: 1) }
        #expect(throws: (any Error).self) { try ProviderStream(provider: "remote") }
    }

    @Test func invalidStreamNamespacesRejectAtConstruction() {
        for identity in ["", String(repeating: "s", count: 129), "bad\0namespace"] {
            #expect(throws: (any Error).self) { try ProviderStream(provider: "codex", streamID: identity) }
        }
    }

    @Test func openCodeCapacityIsReportedAndExistingWorkDegradesOnDisconnect() throws {
        var stream = try ProviderStream(provider: "opencode", streamID: "bounded-open")
        func line(_ index: Int) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": index == 0 || index == 64 ? "busy" : "idle", "sessionID": "s-\(index)"])
        }
        for index in 0..<64 { #expect(try stream.consume(line(index), now: 1).count == 1) }
        #expect(throws: IPCError.policyDenied("adapterCapacityFull")) { try stream.consume(line(64), now: 2) }
        let outstanding = try stream.disconnected(now: 3)
        #expect(outstanding.count == 1 && outstanding.first?.sessionID == "s-0" && outstanding.first?.state == .unknown)
    }

    @Test func maximumLengthRunsKeepSequenceAndChildIdentity() throws {
        var stream = try ProviderStream(provider: "codex")
        let parent = String(repeating: "r", count: 128), child = String(repeating: "c", count: 128)
        func line(_ hook: String, childID: String? = nil) throws -> Data {
            var object = ["type": hook, "thread_id": "s", "turn_id": parent]
            object["agent_id"] = childID
            return try JSONSerialization.data(withJSONObject: object)
        }
        let started = try #require(stream.consume(line("turn.started"), now: 1).first)
        let spawned = try #require(stream.consume(line("subagent.start", childID: child), now: 2).first)
        let settled = try #require(stream.consume(line("turn.completed"), now: 3).first)
        try validateID(started.runID); try validateID(spawned.runID)
        #expect(started.runID.hasPrefix("stream-"))
        #expect(spawned.parentRunID == started.runID && spawned.runID != started.runID)
        #expect(settled.runID == started.runID && settled.sequence == 1)
    }

    @Test func slashContainingNamespaceTuplesCannotAliasAcrossStreams() throws {
        var first = try ProviderStream(provider: "codex", streamID: "a/b")
        var second = try ProviderStream(provider: "codex", streamID: "a")
        let firstLine = Data(#"{"type":"turn.started","thread_id":"s","turn_id":"c"}"#.utf8)
        let secondLine = Data(#"{"type":"turn.started","thread_id":"s","turn_id":"b/c"}"#.utf8)
        let a = try #require(first.consume(firstLine, now: 1).first)
        let b = try #require(second.consume(secondLine, now: 1).first)
        #expect(a.runID != b.runID)
        var store = RuntimeAgentStore()
        _ = try store.ingest(JSONEncoder().encode(a), now: 1)
        _ = try store.ingest(JSONEncoder().encode(b), now: 1)
        #expect(store.tasks(now: 1).filter { $0.state == .working }.count == 2)
    }
}
