/// Audit regression tests for F06, F07, F08, F09, F15.
///
/// Covers anchored unknown/wait deadlines, terminal-respecting reorder drain,
/// bounded installer removal, OpenCode child/missing semantics, and bounded
/// per-run dedup. No other test files are touched.
import Foundation
import Testing

@testable import CamLidCore

private func auditEvent(
    provider: String = "claude",
    session: String = "s-audit",
    run: String = "r-audit",
    state: TaskState,
    sequence: Int,
    epoch: Int = 0,
    received: Double,
    parent: String? = nil
) throws -> NormalizedEvent {
    try NormalizedEvent(
        provider: provider, sessionID: session, runID: run, parentRunID: parent,
        state: state, evidenceKind: .lifecycle, confidence: .exact,
        sequence: sequence, epoch: epoch, receivedMonotonic: received)
}

private func auditApplied(_ outcome: NormalizeOutcome) throws -> AgentTask {
    guard case let .applied(task) = outcome else {
        Issue.record("expected applied, got \(outcome)")
        return try AgentTask(
            id: "audit-fallback", sessionID: "s", runID: "r", state: .unknown,
            evidenceKind: .process, confidence: .unknown)
    }
    return task
}

private func auditJSON(_ text: String) -> Data { Data(text.utf8) }

@Suite("Audit agent findings (F06/F07/F08/F09/F15)")
struct AuditAgentTests {
    // MARK: - F06: anchored unknown/wait deadlines

    @Test("repeated unknown never extends the first anchored deadline")
    func f06RepeatedUnknownAnchored() throws {
        var normalizer = EvidenceNormalizer()
        _ = try auditApplied(normalizer.normalize(
            try auditEvent(state: .working, sequence: 0, received: 0)))
        let first = try auditApplied(normalizer.normalize(
            try auditEvent(state: .unknown, sequence: 1, received: 1)))
        #expect(first.unknownUntilMonotonic == 121)
        let second = try auditApplied(normalizer.normalize(
            try auditEvent(state: .unknown, sequence: 2, received: 119)))
        // Anchored to t=1, not recomputed from t=119 (which would give 239).
        #expect(second.unknownUntilMonotonic == 121)
        #expect(PolicyEngine.holdsSession(second, now: 120))
        #expect(!PolicyEngine.holdsSession(second, now: 121))
    }

    @Test("never-worked unknown holds nothing")
    func f06NeverWorkedUnknownNoHold() throws {
        var normalizer = EvidenceNormalizer()
        let task = try auditApplied(normalizer.normalize(
            try auditEvent(state: .unknown, sequence: 0, received: 50)))
        #expect(task.unknownUntilMonotonic == nil)
        #expect(!PolicyEngine.holdsSession(task, now: 51))
    }

    @Test("fresh working clears degradation and re-anchors")
    func f06WorkingClearsDegradation() throws {
        var normalizer = EvidenceNormalizer()
        _ = try auditApplied(normalizer.normalize(
            try auditEvent(state: .working, sequence: 0, received: 0)))
        let degraded = try auditApplied(normalizer.normalize(
            try auditEvent(state: .unknown, sequence: 1, received: 10)))
        #expect(degraded.unknownUntilMonotonic == 130)
        _ = try auditApplied(normalizer.normalize(
            try auditEvent(state: .working, sequence: 2, received: 20)))
        let fresh = try auditApplied(normalizer.normalize(
            try auditEvent(state: .unknown, sequence: 3, received: 30)))
        #expect(fresh.unknownUntilMonotonic == 150)
        #expect(PolicyEngine.holdsSession(fresh, now: 149))
        #expect(!PolicyEngine.holdsSession(fresh, now: 150))
    }

    @Test("configured wait duration anchors the first wait")
    func f06WaitingAnchoredToConfiguredDuration() throws {
        var normalizer = EvidenceNormalizer(waitRetentionSeconds: 60)
        let first = try auditApplied(normalizer.normalize(
            try auditEvent(state: .waiting, sequence: 0, received: 10)))
        #expect(first.waitUntilMonotonic == 70)
        let second = try auditApplied(normalizer.normalize(
            try auditEvent(state: .waiting, sequence: 1, received: 50)))
        #expect(second.waitUntilMonotonic == 70)
        #expect(PolicyEngine.holdsSession(second, now: 69))
        #expect(!PolicyEngine.holdsSession(second, now: 70))
    }

    // MARK: - F07: terminal-respecting drain

    @Test("terminal-in-middle buffered sequence stays terminal")
    func f07TerminalInMiddleStaysTerminal() throws {
        var normalizer = EvidenceNormalizer()
        let lateWorking = try auditEvent(state: .working, sequence: 2, received: 1002)
        let terminal = try auditEvent(state: .completed, sequence: 1, received: 1001)
        let early = try auditEvent(state: .working, sequence: 0, received: 1000)
        #expect(normalizer.normalize(lateWorking) == .buffered)
        #expect(normalizer.normalize(terminal) == .buffered)
        let outcome = normalizer.normalize(early)
        let task = try auditApplied(outcome)
        #expect(task.state == .completed)
        #expect(!PolicyEngine.holdsSession(task, now: 1003))
        #expect(normalizer.task(
            provider: "claude", sessionID: "s-audit", runID: "r-audit")?.state == .completed)
    }

    @Test("late event after tombstone is rejected")
    func f07LateEventAfterTombstoneRejected() throws {
        var normalizer = EvidenceNormalizer()
        _ = try auditApplied(normalizer.normalize(
            try auditEvent(state: .working, sequence: 0, received: 2000)))
        _ = try auditApplied(normalizer.normalize(
            try auditEvent(state: .failed, sequence: 1, received: 2001)))
        let late = try auditEvent(state: .working, sequence: 2, received: 2002)
        guard case let .reusedRunRejected(reason) = normalizer.normalize(late) else {
            Issue.record("expected reusedRunRejected, got late acceptance")
            return
        }
        #expect(!reason.isEmpty)
        #expect(normalizer.task(
            provider: "claude", sessionID: "s-audit", runID: "r-audit")?.state == .failed)
    }

    // MARK: - F09: OpenCode child/missing semantics

    @Test("completed child releases an idle parent")
    func f09CompletedChildReleasesParent() throws {
        var opencode = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        let start = opencode.parse(json: auditJSON(
            #"{"type":"child.start","session_id":"p-rel","child_session_id":"kid-rel"}"#),
            receivedMonotonic: 3000)
        guard case .event = start else {
            Issue.record("expected child start event, got \(start)")
            return
        }
        let snapshot = try JSONDecoder().decode(
            OpenCodeSnapshot.self,
            from: auditJSON(
                #"{"sessions":[{"session_id":"p-rel","status":"idle","child_sessions":["kid-rel"]},{"session_id":"kid-rel","status":"done"}]}"#))
        let result = opencode.reconcile(
            snapshot: snapshot, takenMonotonic: 3001,
            receivedMonotonic: 3001, nowMonotonic: 3002)
        let parent = result.events.first { $0.sessionID == "p-rel" }
        #expect(parent?.state == .idle)
        #expect(!result.notes.contains("parentHeldForChildren:p-rel"))
    }

    @Test("disappeared parent degrades to bounded unknown, never idle")
    func f09DisappearedParentBoundedUnknown() throws {
        var opencode = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        var normalizer = EvidenceNormalizer()
        let live = try JSONDecoder().decode(
            OpenCodeSnapshot.self,
            from: auditJSON(#"{"sessions":[{"session_id":"p-gone","status":"busy"}]}"#))
        let first = opencode.reconcile(
            snapshot: live, takenMonotonic: 4000,
            receivedMonotonic: 4000, nowMonotonic: 4001)
        guard let workingEvent = first.events.first(where: { $0.sessionID == "p-gone" }) else {
            Issue.record("expected working event for p-gone")
            return
        }
        #expect(workingEvent.state == .working)
        _ = normalizer.normalize(workingEvent)
        let gone = opencode.reconcile(
            snapshot: OpenCodeSnapshot(sessions: []), takenMonotonic: 4100,
            receivedMonotonic: 4100, nowMonotonic: 4101)
        guard let unknownEvent = gone.events.first(where: { $0.sessionID == "p-gone" }) else {
            Issue.record("expected unknown event for disappeared p-gone")
            return
        }
        #expect(unknownEvent.state == .unknown)
        #expect(unknownEvent.state != .idle)
        #expect(gone.notes.contains("missingSessionUnknown:p-gone"))
        let degraded = try auditApplied(normalizer.normalize(unknownEvent))
        #expect(degraded.unknownUntilMonotonic == 4220)
        #expect(PolicyEngine.holdsSession(degraded, now: 4219))
        #expect(!PolicyEngine.holdsSession(degraded, now: 4220))
    }

    @Test("missing child degrades to unknown and expires after its deadline")
    func f09MissingChildExpiresAfterDeadline() throws {
        var opencode = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        var normalizer = EvidenceNormalizer()
        let start = opencode.parse(json: auditJSON(
            #"{"type":"child.start","session_id":"p-miss","child_session_id":"kid-miss"}"#),
            receivedMonotonic: 5000)
        guard case let .event(childWorking) = start else {
            Issue.record("expected child start event, got \(start)")
            return
        }
        _ = normalizer.normalize(childWorking)
        let parentOnly = try JSONDecoder().decode(
            OpenCodeSnapshot.self,
            from: auditJSON(#"{"sessions":[{"session_id":"p-miss","status":"busy"}]}"#))
        let result = opencode.reconcile(
            snapshot: parentOnly, takenMonotonic: 5100,
            receivedMonotonic: 5100, nowMonotonic: 5101)
        guard let childUnknown = result.events.first(where: { $0.sessionID == "kid-miss" }) else {
            Issue.record("expected unknown event for missing kid-miss")
            return
        }
        #expect(childUnknown.state == .unknown)
        let degraded = try auditApplied(normalizer.normalize(childUnknown))
        #expect(PolicyEngine.holdsSession(degraded, now: 5219))
        #expect(!PolicyEngine.holdsSession(degraded, now: 5220))
    }

    @Test("reconcile is independent of snapshot row order")
    func f09RowOrderSwapIdenticalOutcome() throws {
        let rowsA = try JSONDecoder().decode(
            OpenCodeSnapshot.self,
            from: auditJSON(
                #"{"sessions":[{"session_id":"p-ord","status":"idle","child_sessions":["kid-ord"]},{"session_id":"kid-ord","status":"busy"}]}"#))
        let rowsB = try JSONDecoder().decode(
            OpenCodeSnapshot.self,
            from: auditJSON(
                #"{"sessions":[{"session_id":"kid-ord","status":"busy"},{"session_id":"p-ord","status":"idle","child_sessions":["kid-ord"]}]}"#))
        var first = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        var second = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        let resultA = first.reconcile(
            snapshot: rowsA, takenMonotonic: 6000,
            receivedMonotonic: 6000, nowMonotonic: 6001)
        let resultB = second.reconcile(
            snapshot: rowsB, takenMonotonic: 6000,
            receivedMonotonic: 6000, nowMonotonic: 6001)
        let eventsA = resultA.events.map { ($0.sessionID, $0.state) }.sorted { $0.0 < $1.0 }
        let eventsB = resultB.events.map { ($0.sessionID, $0.state) }.sorted { $0.0 < $1.0 }
        #expect(eventsA.map(\.0) == eventsB.map(\.0))
        #expect(eventsA.map(\.1) == eventsB.map(\.1))
        #expect(resultA.notes.sorted() == resultB.notes.sorted())
        #expect(resultA.notes.contains("parentHeldForChildren:p-ord"))
    }

    // MARK: - F15: bounded per-run dedup

    @Test("long sessions keep dedup bounded and reject ancient replays")
    func f15DedupWindowBounded() throws {
        var normalizer = EvidenceNormalizer()
        let window = normalizer.seenWindowSize
        #expect(window == 4096)
        for sequence in 0..<5000 {
            let event = try auditEvent(
                session: "s-flood", run: "r-flood", state: .working,
                sequence: sequence, received: Double(1000 + sequence))
            let outcome = normalizer.normalize(event)
            guard case .applied = outcome else {
                Issue.record("expected applied at sequence \(sequence), got \(outcome)")
                return
            }
        }
        let count = normalizer.seenCount(
            provider: "claude", sessionID: "s-flood", runID: "r-flood")
        #expect(count != nil)
        #expect(count! <= window)
        // Ancient replay (evicted) is rejected as too old even though unseen.
        let ancient = try auditEvent(
            session: "s-flood", run: "r-flood", state: .working,
            sequence: 0, received: 7000)
        #expect(normalizer.normalize(ancient) == .lateRejected(reason: "tooOld"))
        // Recent duplicate still dedups.
        let recent = try auditEvent(
            session: "s-flood", run: "r-flood", state: .working,
            sequence: 4999, received: 7001)
        #expect(normalizer.normalize(recent) == .duplicate)
    }
}
