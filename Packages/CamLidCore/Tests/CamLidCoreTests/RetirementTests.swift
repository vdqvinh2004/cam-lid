import Testing

@testable import CamLidCore

private func retireEvent(
    session: String = "s", run: String, state: TaskState, sequence: Int,
    epoch: Int = 0, received: Double = 1000
) throws -> NormalizedEvent {
    try NormalizedEvent(
        provider: "opencode", sessionID: session, runID: run, parentRunID: nil,
        state: state, evidenceKind: .lifecycle, confidence: .exact,
        sequence: sequence, epoch: epoch, receivedMonotonic: received)
}

private func closeRun(
    _ normalizer: inout EvidenceNormalizer, run: String, at received: Double,
    session: String = "s", sequence: Int = 0
) throws {
    let outcome = normalizer.normalize(
        try retireEvent(session: session, run: run, state: .completed, sequence: sequence, received: received))
    guard case .applied = outcome else {
        Issue.record("expected applied close for \(run), got \(outcome)")
        return
    }
}

@Suite("Production run retirement (T012)")
struct RetirementTests {
    @Test("exhaustion retires oldest terminal and accepts the new run")
    func retiresOldestTerminal() throws {
        var normalizer = EvidenceNormalizer(maxTrackedRuns: 2)
        try closeRun(&normalizer, run: "old", at: 1000)
        try closeRun(&normalizer, run: "newer", at: 2000)
        // Table full (2 terminal runs): next run retires "old".
        let outcome = normalizer.normalize(
            try retireEvent(run: "fresh", state: .working, sequence: 0, received: 3000))
        guard case .applied = outcome else {
            Issue.record("expected applied after retirement, got \(outcome)")
            return
        }
        #expect(normalizer.retiredCount == 1)
        // The surviving terminal run is untouched.
        #expect(normalizer.task(provider: "opencode", sessionID: "s", runID: "newer")?.state == .completed)
    }

    @Test("retired replays stay rejected; newer epoch starts fresh")
    func retiredReplayRejected() throws {
        var normalizer = EvidenceNormalizer(maxTrackedRuns: 1)
        try closeRun(&normalizer, run: "r1", at: 1000)
        _ = normalizer.normalize(
            try retireEvent(run: "r2", state: .working, sequence: 0, received: 2000))
        // Same-epoch replay of the retired ID: rejected, never resurrected.
        #expect(normalizer.normalize(
            try retireEvent(run: "r1", state: .working, sequence: 5, received: 3000)
        ) == .lateRejected(reason: "retiredRun"))
        #expect(normalizer.task(provider: "opencode", sessionID: "s", runID: "r1") == nil)
        // A newer epoch cannot bypass the bound or evict another active run.
        #expect(normalizer.normalize(
            try retireEvent(run: "r1", state: .working, sequence: 0, epoch: 1, received: 4000)
        ) == .lateRejected(reason: "runTableFull"))
        #expect(normalizer.trackedRunCount == 1)
        try closeRun(&normalizer, run: "r2", at: 4001, sequence: 1)
        // After the other run ends, the newer epoch can reuse the identity.
        let outcome = normalizer.normalize(
            try retireEvent(run: "r1", state: .working, sequence: 0, epoch: 1, received: 4000))
        guard case .applied = outcome else {
            Issue.record("expected fresh generation, got \(outcome)")
            return
        }
        #expect(normalizer.retiredCount == 1)
    }

    @Test("full table of active runs rejects without evicting work")
    func activeRunsNeverEvicted() throws {
        var normalizer = EvidenceNormalizer(maxTrackedRuns: 2)
        for run in ["a", "b"] {
            let outcome = normalizer.normalize(
                try retireEvent(run: run, state: .working, sequence: 0, received: 1000))
            guard case .applied = outcome else {
                Issue.record("expected applied for \(run)")
                return
            }
        }
        #expect(normalizer.normalize(
            try retireEvent(run: "c", state: .working, sequence: 0, received: 2000)
        ) == .lateRejected(reason: "runTableFull"))
        #expect(normalizer.retiredCount == 0)
        // Both active runs intact and addressable.
        #expect(normalizer.task(provider: "opencode", sessionID: "s", runID: "a")?.state == .working)
        #expect(normalizer.task(provider: "opencode", sessionID: "s", runID: "b")?.state == .working)
    }

    @Test("retired history exhaustion fails closed and never forgets replay protection")
    func retiredBounded() throws {
        var normalizer = EvidenceNormalizer(maxTrackedRuns: 1, maxRetiredTombstones: 2)
        try closeRun(&normalizer, run: "r1", at: 1000)
        for (run, at) in [("r2", 2000.0), ("r3", 3000.0)] {
            let outcome = normalizer.normalize(
                try retireEvent(run: run, state: .working, sequence: 0, received: at))
            guard case .applied = outcome else {
                Issue.record("expected applied for \(run)")
                return
            }
            // Close each newcomer (next sequence) so the next arrival retires again.
            try closeRun(&normalizer, run: run, at: at + 1, sequence: 1)
        }
        #expect(normalizer.retiredCount == 2)
        #expect(normalizer.normalize(try retireEvent(run: "r4", state: .working, sequence: 0, received: 5000)) == .lateRejected(reason: "retirementHistoryFull"))
        #expect(normalizer.normalize(try retireEvent(run: "r1", state: .working, sequence: 0, received: 5001)) == .lateRejected(reason: "retiredRun"))
        #expect(normalizer.task(provider: "opencode", sessionID: "s", runID: "r3")?.state == .completed)
        normalizer.endSession(provider: "opencode", sessionID: "s")
        #expect(normalizer.retiredCount == 0)
        guard case .applied = normalizer.normalize(try retireEvent(run: "r4", state: .working, sequence: 0, received: 5002)) else { Issue.record("Explicit session end must free capacity"); return }
    }

    @Test func retiringParentNeverRemovesAnotherSessionsChildLinks() throws {
        var normalizer = EvidenceNormalizer(maxTrackedRuns: 3)
        try closeRun(&normalizer, run: "main", at: 1000, session: "a")
        _ = normalizer.normalize(try retireEvent(session: "b", run: "main", state: .working, sequence: 0, received: 1001))
        _ = normalizer.normalize(try NormalizedEvent(provider: "opencode", sessionID: "b", runID: "child", parentRunID: "main",
            state: .working, evidenceKind: .lifecycle, confidence: .exact, sequence: 0, receivedMonotonic: 1002))
        _ = normalizer.normalize(try retireEvent(run: "fresh", state: .working, sequence: 0, received: 1003))
        #expect(normalizer.childRunIDs(provider: "opencode", sessionID: "b", parentRunID: "main") == ["child"])
    }

    @Test("endSession clears retired tombstones for the session")
    func endSessionClearsRetired() throws {
        var normalizer = EvidenceNormalizer(maxTrackedRuns: 1)
        try closeRun(&normalizer, run: "r1", at: 1000)
        _ = normalizer.normalize(
            try retireEvent(run: "r2", state: .working, sequence: 0, received: 2000))
        #expect(normalizer.retiredCount == 1)
        normalizer.endSession(provider: "opencode", sessionID: "s")
        #expect(normalizer.retiredCount == 0)
        let outcome = normalizer.normalize(
            try retireEvent(run: "r1", state: .working, sequence: 0, received: 3000))
        guard case .applied = outcome else {
            Issue.record("expected fresh reuse after endSession, got \(outcome)")
            return
        }
    }
}
