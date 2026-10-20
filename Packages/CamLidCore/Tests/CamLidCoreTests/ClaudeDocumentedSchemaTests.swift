import Foundation
import Testing

@testable import CamLidCore

private func documentedJSON(_ text: String) -> Data { Data(text.utf8) }

@Suite("Claude documented hook schema")
struct ClaudeDocumentedSchemaTests {
    @Test("documented event key and prompt UUID become bounded exact turn identity")
    func promptIdentityAndPrivacy() throws {
        let promptID = "550e8400-e29b-41d4-a716-446655440000"
        let input = documentedJSON(#"{"hook_event_name":"UserPromptSubmit","session_id":"claude-session","prompt_id":"550e8400-e29b-41d4-a716-446655440000","transcript_path":"/private/TRANSCRIPT_SECRET","cwd":"/private/CWD_SECRET","prompt":"PROMPT_SECRET"}"#)
        var adapter = ClaudeAdapter(optIn: true, providerVersion: "2.1.196")
        guard case let .event(event) = adapter.parse(json: input, receivedMonotonic: 100) else {
            Issue.record("expected documented UserPromptSubmit payload to produce an event")
            return
        }

        #expect(event.state == .working)
        #expect(event.runID == promptID)
        #expect(event.confidence == .exact)
        let rendered = String(reflecting: event)
        #expect(!rendered.contains("TRANSCRIPT_SECRET"))
        #expect(!rendered.contains("CWD_SECRET"))
        #expect(!rendered.contains("PROMPT_SECRET"))
    }

    @Test("known provider version gates prompt identity and fallback is explicitly inferred")
    func promptIdentityVersionGate() throws {
        let input = documentedJSON(#"{"hook_event_name":"UserPromptSubmit","session_id":"s-version","prompt_id":"550e8400-e29b-41d4-a716-446655440001"}"#)

        var supported = ClaudeAdapter(optIn: true, providerVersion: "2.1.196")
        guard case let .event(exact) = supported.parse(json: input, receivedMonotonic: 1) else {
            Issue.record("expected supported-version event")
            return
        }
        #expect(exact.runID == "550e8400-e29b-41d4-a716-446655440001")
        #expect(exact.confidence == .exact)

        var older = ClaudeAdapter(optIn: true, providerVersion: "2.1.195")
        guard case let .event(inferred) = older.parse(json: input, receivedMonotonic: 1) else {
            Issue.record("older version should retain conservative session-level observation")
            return
        }
        #expect(inferred.runID == "main")
        #expect(inferred.confidence == .inferred)

        var versionUnknown = ClaudeAdapter(optIn: true)
        guard case let .event(fieldVerified) = versionUnknown.parse(json: input, receivedMonotonic: 1) else {
            Issue.record("present prompt_id is usable when provider version is unknown")
            return
        }
        #expect(fieldVerified.runID == "550e8400-e29b-41d4-a716-446655440001")
        #expect(fieldVerified.confidence == .exact)
    }

    @Test("Stop counts only running object rows; terminal rows and cron wakeups do not hold")
    func backgroundTaskStatusAndPrivacy() throws {
        let promptID = "550e8400-e29b-41d4-a716-446655440002"
        let active = documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-background","prompt_id":"550e8400-e29b-41d4-a716-446655440002","background_tasks":[{"id":"bg-1","type":"shell","status":"running","description":"DESCRIPTION_SECRET","command":"COMMAND_SECRET"}],"session_crons":[{"id":"cron-1","schedule":"0 9 * * 1-5","recurring":true,"prompt":"CRON_PROMPT_SECRET"}],"last_assistant_message":"MESSAGE_SECRET"}"#)
        var adapter = ClaudeAdapter(optIn: true, providerVersion: "2.1.220")
        let decoded = try JSONDecoder().decode(ClaudeHookPayload.self, from: active)
        #expect(decoded.backgroundTaskCount == 1)
        #expect(decoded.hasBackgroundTaskSnapshot)
        #expect(decoded.sessionCronCount == 1)
        let payloadRendered = String(reflecting: decoded)
        #expect(!payloadRendered.contains("DESCRIPTION_SECRET"))
        #expect(!payloadRendered.contains("COMMAND_SECRET"))
        #expect(!payloadRendered.contains("CRON_PROMPT_SECRET"))
        #expect(!payloadRendered.contains("MESSAGE_SECRET"))

        guard case let .event(activeEvent) = adapter.parse(json: active, receivedMonotonic: 10) else {
            Issue.record("expected active background task event")
            return
        }
        #expect(activeEvent.state == .working)
        #expect(activeEvent.runID == promptID)
        #expect(adapter.backgroundTaskCount(sessionID: "s-background") == 1)
        let eventRendered = String(reflecting: activeEvent)
        #expect(!eventRendered.contains("DESCRIPTION_SECRET"))
        #expect(!eventRendered.contains("COMMAND_SECRET"))
        #expect(!eventRendered.contains("CRON_PROMPT_SECRET"))

        var normalizer = EvidenceNormalizer()
        _ = normalizer.normalize(activeEvent)
        let held = try #require(normalizer.task(
            provider: "claude", sessionID: "s-background", runID: promptID))
        #expect(PolicyEngine.holdsSession(held, now: 11))

        let terminal = documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-background","prompt_id":"550e8400-e29b-41d4-a716-446655440002","background_tasks":[{"id":"bg-1","type":"shell","status":"completed","description":"TERMINAL_SECRET"}],"session_crons":[]}"#)
        guard case let .event(terminalEvent) = adapter.parse(json: terminal, receivedMonotonic: 12) else {
            Issue.record("expected terminal background snapshot")
            return
        }
        #expect(terminalEvent.state == .idle)
        #expect(adapter.backgroundTaskCount(sessionID: "s-background") == 0)
        _ = normalizer.normalize(terminalEvent)
        let released = try #require(normalizer.task(
            provider: "claude", sessionID: "s-background", runID: promptID))
        #expect(!PolicyEngine.holdsSession(released, now: 13))
        #expect(!String(reflecting: terminalEvent).contains("TERMINAL_SECRET"))

        let cronOnly = documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-cron","prompt_id":"550e8400-e29b-41d4-a716-446655440003","background_tasks":[],"session_crons":[{"id":"cron-2","schedule":"0 10 * * *","recurring":false,"prompt":"FUTURE_PROMPT_SECRET"}]}"#)
        guard case let .event(cronEvent) = adapter.parse(json: cronOnly, receivedMonotonic: 20) else {
            Issue.record("expected cron-only Stop event")
            return
        }
        #expect(cronEvent.state == .idle)
        #expect(adapter.backgroundTaskCount(sessionID: "s-cron") == 0)
        #expect(!String(reflecting: cronEvent).contains("FUTURE_PROMPT_SECRET"))
    }

    @Test("subagent identity links to its prompt and only its terminal event retires it")
    func subagentLifecycle() throws {
        let promptID = "550e8400-e29b-41d4-a716-446655440004"
        var adapter = ClaudeAdapter(optIn: true, providerVersion: "2.1.220")
        let startJSON = documentedJSON(#"{"hook_event_name":"SubagentStart","session_id":"s-child","prompt_id":"550e8400-e29b-41d4-a716-446655440004","agent_id":"agent-44","agent_type":"Explore","transcript_path":"TRANSCRIPT_SECRET","cwd":"CWD_SECRET"}"#)
        guard case let .event(start) = adapter.parse(json: startJSON, receivedMonotonic: 30) else {
            Issue.record("expected SubagentStart event")
            return
        }
        #expect(start.state == .working)
        #expect(start.runID == "agent-44")
        #expect(start.parentRunID == promptID)
        #expect(start.confidence == .exact)
        let rendered = String(reflecting: start)
        #expect(!rendered.contains("TRANSCRIPT_SECRET"))
        #expect(!rendered.contains("CWD_SECRET"))

        var normalizer = EvidenceNormalizer()
        _ = normalizer.normalize(start)
        let held = try #require(normalizer.task(
            provider: "claude", sessionID: "s-child", runID: "agent-44"))
        #expect(PolicyEngine.holdsSession(held, now: 31))

        let stopJSON = documentedJSON(#"{"hook_event_name":"SubagentStop","session_id":"s-child","prompt_id":"550e8400-e29b-41d4-a716-446655440004","agent_id":"agent-44","agent_type":"Explore","agent_transcript_path":"AGENT_TRANSCRIPT_SECRET","last_assistant_message":"FINAL_MESSAGE_SECRET","background_tasks":[],"session_crons":[]}"#)
        guard case let .event(stop) = adapter.parse(json: stopJSON, receivedMonotonic: 32) else {
            Issue.record("expected SubagentStop event")
            return
        }
        #expect(stop.state == .completed)
        #expect(stop.runID == "agent-44")
        #expect(stop.parentRunID == promptID)
        _ = normalizer.normalize(stop)
        let released = try #require(normalizer.task(
            provider: "claude", sessionID: "s-child", runID: "agent-44"))
        #expect(!PolicyEngine.holdsSession(released, now: 33))
        let stopRendered = String(reflecting: stop)
        #expect(!stopRendered.contains("AGENT_TRANSCRIPT_SECRET"))
        #expect(!stopRendered.contains("FINAL_MESSAGE_SECRET"))
    }

    @Test("unknown statuses and notifications never imply idle or completion")
    func conservativeUnknowns() {
        var adapter = ClaudeAdapter(optIn: true)
        let unknownTask = documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-unknown","prompt_id":"prompt-unknown","background_tasks":[{"id":"bg-2","status":"provider-added-state"}],"session_crons":[]}"#)
        guard case let .event(unknown) = adapter.parse(json: unknownTask, receivedMonotonic: 40) else {
            Issue.record("expected bounded unknown event for unrecognized background status")
            return
        }
        #expect(unknown.state == .unknown)
        #expect(unknown.confidence == .exact)

        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"Notification","session_id":"s-unknown","notification_type":"idle_prompt"}"#),
            receivedMonotonic: 41) == .ignored(reason: "idlePromptNotCompletion"))
        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"Notification","session_id":"s-unknown","notification_type":"future_notification"}"#),
            receivedMonotonic: 42) == .ignored(reason: "unknownNotification"))
        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"Notification","session_id":"s-unknown","notification_type":"permission_prompt"}"#),
            receivedMonotonic: 43).eventState == .waiting)

        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"Interrupt","session_id":"s-unknown","prompt_id":"prompt-unknown"}"#),
            receivedMonotonic: 44) == .ignored(reason: "noInterruptHook"))
    }

    @Test("inferred session sequence survives repeated turns and closes cleanly across reconnect")
    func inferredSessionSequenceAndLifecycle() throws {
        var adapter = ClaudeAdapter(optIn: true)
        var normalizer = EvidenceNormalizer()
        let session = "s-multiturn"

        guard let start = adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"SessionStart","session_id":"s-multiturn"}"#),
            receivedMonotonic: 1).normalizedEvent
        else {
            Issue.record("expected SessionStart to produce conservative unknown evidence")
            return
        }
        #expect(start.state == .unknown)
        guard case let .applied(startTask) = normalizer.normalize(start) else {
            Issue.record("expected SessionStart unknown evidence to apply")
            return
        }
        #expect(startTask.state == .unknown)
        #expect(!PolicyEngine.holdsSession(startTask, now: 2))

        var previousSequence = start.sequence
        for turn in 1...3 {
            guard let prompt = adapter.parse(
                json: documentedJSON(#"{"hook_event_name":"UserPromptSubmit","session_id":"s-multiturn"}"#),
                receivedMonotonic: Double(turn * 10)).normalizedEvent
            else {
                Issue.record("turn \(turn) did not produce UserPromptSubmit evidence")
                return
            }
            #expect(prompt.runID == "main")
            #expect(prompt.confidence == .inferred)
            #expect(prompt.sequence == previousSequence + 1)
            previousSequence = prompt.sequence
            guard case let .applied(promptTask) = normalizer.normalize(prompt) else {
                Issue.record("turn \(turn) prompt was dropped or reordered")
                return
            }
            #expect(promptTask.state == .working)
            #expect(PolicyEngine.holdsSession(promptTask, now: Double(turn * 10) + 1))

            guard let stop = adapter.parse(
                json: documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-multiturn","background_tasks":[]}"#),
                receivedMonotonic: Double(turn * 10 + 1)).normalizedEvent
            else {
                Issue.record("turn \(turn) did not produce Stop evidence")
                return
            }
            #expect(stop.sequence == previousSequence + 1)
            previousSequence = stop.sequence
            guard case let .applied(stopTask) = normalizer.normalize(stop) else {
                Issue.record("turn \(turn) Stop was dropped or reordered")
                return
            }
            #expect(stopTask.state == .idle)
            #expect(!PolicyEngine.holdsSession(stopTask, now: Double(turn * 10 + 2)))
            if case .duplicate = normalizer.normalize(stop) {
                // Replaying the exact same provider event cannot change the task.
            } else {
                Issue.record("replaying Stop evidence must be idempotent")
                return
            }

            // A second Stop hook has a fresh sequence but leaves the session idle.
            guard let repeatedStop = adapter.parse(
                json: documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-multiturn","background_tasks":[]}"#),
                receivedMonotonic: Double(turn * 10 + 2)).normalizedEvent
            else {
                Issue.record("repeated Stop did not produce an event")
                return
            }
            #expect(repeatedStop.sequence == previousSequence + 1)
            previousSequence = repeatedStop.sequence
            guard case let .applied(repeatedStopTask) = normalizer.normalize(repeatedStop) else {
                Issue.record("repeated Stop must preserve monotonically ordered idle evidence")
                return
            }
            #expect(repeatedStopTask.state == .idle)
        }

        // A stream reconnect starts a fresh event epoch, and the normalizer's
        // documented epoch-reset handshake applies the retried observation.
        adapter.noteReconnect(sessionID: session)
        guard let afterReconnect = adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"UserPromptSubmit","session_id":"s-multiturn"}"#),
            receivedMonotonic: 40).normalizedEvent
        else {
            Issue.record("reconnected stream did not produce new work evidence")
            return
        }
        #expect(afterReconnect.epoch == 1)
        #expect(afterReconnect.sequence == 0)
        guard case .epochReset(newEpoch: 1) = normalizer.normalize(afterReconnect) else {
            Issue.record("reconnect must begin a new normalizer epoch")
            return
        }
        guard case let .applied(reconnectedTask) = normalizer.normalize(afterReconnect) else {
            Issue.record("fresh reconnect evidence was not applied after epoch reset")
            return
        }
        #expect(reconnectedTask.state == .working)

        guard let ended = adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"SessionEnd","session_id":"s-multiturn"}"#),
            receivedMonotonic: 41).normalizedEvent
        else {
            Issue.record("SessionEnd did not produce a terminal event")
            return
        }
        #expect(ended.sequence == 1)
        #expect(ended.epoch == 1)
        guard case let .applied(endedTask) = normalizer.normalize(ended) else {
            Issue.record("SessionEnd should close the active session run")
            return
        }
        #expect(endedTask.state == .completed)
        #expect(adapter.backgroundTaskCount(sessionID: session) == 0)

        // A stale callback after SessionEnd cannot reuse the terminal run ID.
        guard let staleAfterEnd = adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"UserPromptSubmit","session_id":"s-multiturn"}"#),
            receivedMonotonic: 42).normalizedEvent
        else {
            Issue.record("post-end callback should be rejected by normalizer, not malformed")
            return
        }
        #expect(staleAfterEnd.sequence == 0)
        if case .lateRejected = normalizer.normalize(staleAfterEnd) {
            // The same closed provider session cannot resurrect its terminal run.
        } else {
            Issue.record("post-SessionEnd callback resurrected a terminal run")
        }
    }

    @Test("oversize, malformed, and unbounded routing values reject with reasons")
    func boundedDecode() {
        var adapter = ClaudeAdapter(optIn: true)
        #expect(adapter.parse(
            json: Data(repeating: 0x20, count: PolicyLimits.maxEventBytes + 1),
            receivedMonotonic: 1) == .ignored(reason: "eventTooLarge"))
        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-bad","background_tasks":"not-an-array"}"#),
            receivedMonotonic: 2) == .ignored(reason: "invalidBackgroundTasks"))
        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":"Stop","session_id":"s-bad","session_crons":"not-an-array"}"#),
            receivedMonotonic: 3) == .ignored(reason: "invalidSessionCrons"))
        #expect(adapter.parse(
            json: documentedJSON(#"{"hook_event_name":7,"session_id":"s-bad"}"#),
            receivedMonotonic: 4) == .ignored(reason: "invalidPayloadType"))

        let tooLong = String(repeating: "x", count: PolicyLimits.maxIDLength + 1)
        let invalidPrompt = documentedJSON(#"{"hook_event_name":"UserPromptSubmit","session_id":"s-bad","prompt_id":"\#(tooLong)"}"#)
        #expect(adapter.parse(json: invalidPrompt, receivedMonotonic: 5)
            == .ignored(reason: "invalidPromptID"))

        #expect(adapter.parse(
            json: documentedJSON(#"{"session_id":"s-bad"}"#),
            receivedMonotonic: 6) == .ignored(reason: "missingHookEvent"))
    }

    @Test("legacy parser fixtures remain accepted while synthetic interrupt is rejected")
    func syntheticCompatibility() {
        var adapter = ClaudeAdapter(optIn: true)
        guard case let .event(prompt) = adapter.parse(
            json: documentedJSON(#"{"hook":"UserPromptSubmit","session_id":"s-legacy"}"#),
            receivedMonotonic: 1) else {
            Issue.record("expected old fixture alias to remain accepted")
            return
        }
        #expect(prompt.runID == "main")
        #expect(prompt.confidence == .inferred)

        guard case let .event(child) = adapter.parse(
            json: documentedJSON(#"{"hook":"SubagentStart","session_id":"s-legacy","subagent_id":"child-1"}"#),
            receivedMonotonic: 2) else {
            Issue.record("expected old child fixture alias to remain accepted")
            return
        }
        #expect(child.parentRunID == "main")

        #expect(adapter.parse(
            json: documentedJSON(#"{"hook":"Interrupt","session_id":"s-legacy"}"#),
            receivedMonotonic: 3) == .ignored(reason: "noInterruptHook"))
    }
}

private extension ClaudeParseResult {
    var normalizedEvent: NormalizedEvent? {
        guard case let .event(event) = self else { return nil }
        return event
    }

    var eventState: TaskState? {
        guard case let .event(event) = self else { return nil }
        return event.state
    }
}
