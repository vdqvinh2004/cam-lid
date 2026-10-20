import Foundation
import CryptoKit

/// A failed tool is an outcome inside a turn, not proof the agent turn failed.
/// Contains no command, prompt, output or path.
public struct ProviderToolOutcome: Codable, Equatable, Sendable {
    public let status: String
    public let exitCode: Int?
    public var failed: Bool { status == "failed" || (exitCode.map { $0 != 0 } ?? false) }
    public init(status: String, exitCode: Int?) { self.status = status; self.exitCode = exitCode }
}

/// One instance per producer stream. Provider IDs and sequences cannot bleed
/// between simultaneous exec processes. Input is never retained or logged.
public struct ProviderStream: Sendable {
    public let provider: String
    private var codex = CodexAdapter(optIn: true)
    private var opencode = OpenCodeAdapter(optIn: true, endpoint: "stdin")
    private let streamID: String
    private var runs: [String: NormalizedEvent] = [:]
    private var generations: [String: Int] = [:]
    private var unsupportedCodexCollaboration = false
    public private(set) var lastToolOutcome: ProviderToolOutcome?

    public init(provider: String, streamID: String = UUID().uuidString) throws {
        guard ["codex", "opencode"].contains(provider) else { throw IPCError.invalidInput("unsupportedStreamProvider") }
        try validateID(streamID)
        self.provider = provider; self.streamID = streamID
    }

    public mutating func consume(_ line: Data, now: Double) throws -> [NormalizedEvent] {
        guard !unsupportedCodexCollaboration else {
            throw IPCError.policyDenied("codexCollaborationUnsupported")
        }
        _ = try BoundedPayload(line)
        guard (try? JSONSerialization.jsonObject(with: line)) is [String: Any] else { throw IPCError.invalidInput("invalidStreamJSON") }
        lastToolOutcome = nil
        let parsed: NormalizedEvent?
        if provider == "codex" {
            let result = codex.parse(json: line, receivedMonotonic: now)
            lastToolOutcome = codex.lastToolOutcome
            switch result {
            case .event(let event): parsed = event
            case .ignored(let reason) where reason == "codexCollaborationUnsupported":
                unsupportedCodexCollaboration = true
                throw IPCError.policyDenied(reason)
            case .ignored(let reason) where reason == "adapterCapacityFull" || reason == "counterExhausted":
                throw IPCError.policyDenied(reason)
            case .ignored: parsed = nil
            }
        } else {
            switch opencode.parse(json: line, receivedMonotonic: now) {
            case .event(let event): parsed = event
            case .ignored(let reason) where reason == "adapterCapacityFull" || reason == "counterExhausted":
                throw IPCError.policyDenied(reason)
            case .ignored: parsed = nil
            }
        }
        guard let parsed else { return [] }
        let key = parsed.sessionID + "\0" + parsed.runID
        guard runs[key] != nil || runs.count < 64 else { throw IPCError.policyDenied("streamRunCapacity") }
        let previous = runs[key]
        let wasTerminal = previous.map { [.completed, .failed].contains($0.state) } ?? false
        if wasTerminal && parsed.state == .working { generations[key, default: 0] += 1 }
        let generation = generations[key, default: 0]
        let run = namespacedRun(parsed.runID, generation: generation)
        let sequence = previous?.runID == run ? (previous!.sequence + 1) : 0
        let event = try NormalizedEvent(provider: provider, sessionID: parsed.sessionID, runID: run,
            parentRunID: parsed.parentRunID.map { namespacedRun($0, generation: generations[parsed.sessionID + "\0" + $0, default: 0]) },
            state: parsed.state, evidenceKind: parsed.evidenceKind, confidence: parsed.confidence,
            sequence: sequence, receivedMonotonic: now)
        runs[key] = event
        return [event]
    }

    /// Preserve short existing IDs; hash tuples that exceed the shared bound
    /// or could alias when slash-containing components are concatenated.
    private func namespacedRun(_ run: String, generation: Int) -> String {
        let readable = "\(streamID)/\(run)/\(generation)"
        if readable.count <= PolicyLimits.maxIDLength && !streamID.contains("/") && !run.contains("/") {
            return readable
        }
        let tuple = Data("\(streamID)\0\(run)\0\(generation)".utf8)
        return "stream-" + SHA256.hash(data: tuple).map { String(format: "%02x", $0) }.joined()
    }

    /// A closed or malformed stream cannot prove completion. It immediately
    /// degrades outstanding work; no process-presence heartbeat fabricates work.
    public mutating func disconnected(now: Double) throws -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        for key in runs.keys.sorted() {
            guard let old = runs[key], [.working, .waiting].contains(old.state)
                || (unsupportedCodexCollaboration && old.state == .idle) else { continue }
            // Unsupported child evidence also invalidates an earlier idle;
            // the public parent turn does not account for child lifetime.
            let event = try NormalizedEvent(provider: provider, sessionID: old.sessionID, runID: old.runID,
                parentRunID: old.parentRunID, state: .unknown, evidenceKind: .lifecycle,
                confidence: .unknown, sequence: old.sequence + 1, receivedMonotonic: now)
            runs[key] = event; events.append(event)
        }
        return events
    }
}
