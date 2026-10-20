import Foundation
import Testing
@testable import CamLidCore

struct CodexCapacityTests {
    @Test func runCapacityPreservesExistingCountersUntilExplicitCleanup() throws {
        var adapter = CodexAdapter(optIn: true)
        for index in 0..<64 {
            _ = try event(adapter.parse(CodexEventPayload(hook: "turn.started", sessionID: "s", turnID: "r-\(index)"), receivedMonotonic: 1))
        }
        #expect(adapter.parse(CodexEventPayload(hook: "turn.started", sessionID: "overflow"), receivedMonotonic: 2) == .ignored(reason: "adapterCapacityFull"))
        let retained = try event(adapter.parse(CodexEventPayload(hook: "turn.completed", sessionID: "s", turnID: "r-0"), receivedMonotonic: 3))
        #expect(retained.sequence == 1 && retained.state == .idle)
        adapter.forgetSession("s")
        let fresh = try event(adapter.parse(CodexEventPayload(hook: "turn.started", sessionID: "overflow"), receivedMonotonic: 4))
        #expect(fresh.sequence == 0)
    }

    @Test func threadTrackingHasItsOwnBoundAndRejectsWithoutChangingAssociation() throws {
        var adapter = CodexAdapter(optIn: true)
        for index in 0..<64 {
            #expect(adapter.parse(CodexEventPayload(hook: "thread.started", sessionID: "s-\(index)"), receivedMonotonic: 1) == .ignored(reason: "threadTracked"))
        }
        #expect(adapter.parse(CodexEventPayload(hook: "thread.started", sessionID: "overflow"), receivedMonotonic: 2) == .ignored(reason: "adapterCapacityFull"))
        let retained = try event(adapter.parse(CodexEventPayload(hook: "turn.started"), receivedMonotonic: 3))
        #expect(retained.sessionID == "s-63")
        adapter.forgetSession("s-0")
        #expect(adapter.parse(CodexEventPayload(hook: "thread.started", sessionID: "overflow"), receivedMonotonic: 4) == .ignored(reason: "threadTracked"))
    }

    @Test func rejectedEventsDoNotPoisonActiveTurnOrStreamAssociation() throws {
        var adapter = CodexAdapter(optIn: true)
        _ = try event(adapter.parse(CodexEventPayload(hook: "turn.started", sessionID: "good", turnID: "turn"), receivedMonotonic: 1))
        for payload in [
            CodexEventPayload(hook: "turn.started", sessionID: "bad\0session"),
            CodexEventPayload(hook: "turn.started", sessionID: "other", turnID: "bad\nturn"),
            CodexEventPayload(hook: "subagent.start", sessionID: "other", agentID: "bad\tchild")
        ] {
            #expect(adapter.parse(payload, receivedMonotonic: 2) == .ignored(reason: "invalidIdentity"))
        }
        #expect(adapter.parse(CodexEventPayload(hook: "unrecognized", sessionID: "attacker"), receivedMonotonic: 2) == .ignored(reason: "unknownHook"))
        #expect(adapter.activeTurnID(sessionID: "good") == "turn")
        #expect(adapter.activeTurnID(sessionID: "other") == nil)
        let retained = try event(adapter.parse(CodexEventPayload(hook: "turn.completed", turnID: "turn"), receivedMonotonic: 3))
        #expect(retained.sessionID == "good" && retained.sequence == 1)
    }

    @Test func invalidReceiptDoesNotConsumeSequenceOrRememberIdentity() throws {
        var adapter = CodexAdapter(optIn: true)
        let payload = CodexEventPayload(hook: "turn.started", sessionID: "s", turnID: "r")
        #expect(adapter.parse(payload, receivedMonotonic: .nan) == .ignored(reason: "invalidIdentity"))
        #expect(adapter.activeTurnID(sessionID: "s") == nil)
        #expect(adapter.parse(CodexEventPayload(hook: "turn.started"), receivedMonotonic: 1) == .ignored(reason: "missingSessionID"))
        #expect(try event(adapter.parse(payload, receivedMonotonic: 2)).sequence == 0)
    }

    @Test func reconnectCannotBypassIdentityCapacityAndRetainsExistingEpoch() throws {
        var adapter = CodexAdapter(optIn: true)
        for index in 0..<64 {
            let accepted = adapter.noteReconnect(sessionID: "s-\(index)")
            #expect(accepted)
        }
        let overflow = adapter.noteReconnect(sessionID: "overflow")
        let invalid = adapter.noteReconnect(sessionID: "bad\0session")
        #expect(!overflow && !invalid)
        let first = try event(adapter.parse(CodexEventPayload(hook: "turn.started", sessionID: "s-0"), receivedMonotonic: 1))
        #expect(first.epoch == 1 && first.sequence == 0)
        let accepted = adapter.noteReconnect(sessionID: "s-0")
        #expect(accepted)
        let reconnected = try event(adapter.parse(CodexEventPayload(hook: "turn.started", sessionID: "s-0"), receivedMonotonic: 2))
        #expect(reconnected.epoch == 2 && reconnected.sequence == 0)
    }

    @Test func streamReportsCapacityRatherThanSilentlyDroppingNewWork() throws {
        var stream = try ProviderStream(provider: "codex", streamID: "bounded-stream")
        func line(_ index: Int) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "turn.started", "thread_id": "s", "turn_id": "r-\(index)"])
        }
        for index in 0..<64 { #expect(try stream.consume(line(index), now: 1).count == 1) }
        #expect(throws: IPCError.policyDenied("adapterCapacityFull")) { try stream.consume(line(64), now: 2) }
        let outstanding = try stream.disconnected(now: 3)
        #expect(outstanding.count == 64 && outstanding.allSatisfy { $0.state == .unknown })
    }

    private func event(_ result: CodexParseResult) throws -> NormalizedEvent {
        guard case let .event(value) = result else { throw UnexpectedParseResult.ignored }
        return value
    }
    private enum UnexpectedParseResult: Error { case ignored }
}
