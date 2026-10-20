import Foundation
import Testing

@testable import CamLidCore

/// Installed-stream regressions (M3 T008): real `codex exec --json` and
/// `opencode run --format json` output captured 2026-10-05 (gpt-6-luna medium,
/// opencode-go/longcat-2.5-preview-free) must flow through the adapters.
/// Golden files live in Fixtures/Matrix/; full 20-run streams stay in
/// docs/qa/preview-evidence/provider-matrix/ (not committed to the target).
private func matrixLines(_ name: String) throws -> [String] {
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let url = here
        .appendingPathComponent("Fixtures/Matrix/\(name)", isDirectory: false)
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
}

private func jsonValue(_ line: String, key: String) throws -> String {
    struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
    let object = try JSONDecoder().decode([String: String].self, from: Data(line.utf8))
    guard let value = object[key] else {
        throw MatrixFixtureError.missingKey(key)
    }
    return value
}

private enum MatrixFixtureError: Error {
    case missingKey(String)
}

@Suite("Installed provider streams (T008)")
struct InstalledStreamsTests {
    @Test("codex exec success stream normalizes working then idle")
    func codexSuccessStream() throws {
        var adapter = CodexAdapter(optIn: true)
        let lines = try matrixLines("codex-success.jsonl")
        let threadID = try jsonValue(lines[0], key: "thread_id")
        var states: [TaskState] = []
        for line in lines {
            if case let .event(event) = adapter.parseJSONLine(line, receivedMonotonic: 1000) {
                states.append(event.state)
            }
        }
        // thread.started tracked; turn.started working (thread-associated);
        // turn.completed idle. item.* lines carry the exec result inline.
        #expect(states == [.working, .idle])
        #expect(adapter.activeTurnID(sessionID: threadID) == "main")
    }

    @Test("codex exec failure surfaces failed exec status inline")
    func codexFailStream() throws {
        var adapter = CodexAdapter(optIn: true)
        var states: [TaskState] = []
        var failedTools = 0
        for line in try matrixLines("codex-fail.jsonl") {
            if case let .event(event) = adapter.parseJSONLine(line, receivedMonotonic: 1000) {
                states.append(event.state)
            }
            if adapter.lastToolOutcome?.failed == true { failedTools += 1 }
        }
        #expect(failedTools > 0)
        // A failed tool is deliberately separate from turn lifecycle.
        #expect(states == [.working, .idle])
    }

    @Test("opencode steps remain working until session end")
    func openCodeStream() throws {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        var states: [TaskState] = []
        for line in try matrixLines("opencode-success.jsonl") {
            guard let data = line.data(using: .utf8) else { continue }
            if case let .event(event) = adapter.parse(json: data, receivedMonotonic: 1000) {
                states.append(event.state)
            }
        }
        // Each step_start confirms work; step_finish is not session completion.
        // tool_use/text lines carry payload detail, not lifecycle transitions.
        #expect(states == [.working, .working])
    }

    @Test("OpenCode tool-call step finish must not tombstone an active session")
    func toolStepNotTerminal() throws {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        var runtime = RuntimeAgentStore()
        for line in try matrixLines("opencode-success.jsonl") {
            if case let .event(event) = adapter.parse(json: Data(line.utf8), receivedMonotonic: 1) {
                _ = try runtime.ingest(JSONEncoder().encode(event), now: 1)
            }
        }
        #expect(runtime.tasks(now: 1).last?.state == .working)
    }

    @Test("session-less lines resolve to the stream thread")
    func threadAssociation() throws {
        var adapter = CodexAdapter(optIn: true)
        let tracked = adapter.parseJSONLine(
            #"{"type":"thread.started","thread_id":"thr-1"}"#, receivedMonotonic: 1)
        guard case .ignored = tracked else {
            Issue.record("expected thread-tracked ignore, got \(tracked)")
            return
        }
        let working = adapter.parseJSONLine(
            #"{"type":"turn.started"}"#, receivedMonotonic: 2)
        guard case let .event(event) = working else {
            Issue.record("expected associated event, got \(working)")
            return
        }
        #expect(event.sessionID == "thr-1")
        #expect(event.state == .working)
        adapter.forgetSession("thr-1")
        #expect(adapter.parseJSONLine(
            #"{"type":"turn.started"}"#, receivedMonotonic: 3
        ) == .ignored(reason: "missingSessionID"))
    }
}
