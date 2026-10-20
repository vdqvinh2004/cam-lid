import Testing

@testable import CamLidCore

private func makeRecord(session: String = "s", owner: String = "uid501", proto: Int = 1) throws
    -> RecoveryRecord
{
    try RecoveryRecord(
        journalRevision: 1, sessionID: session, ownerIdentity: owner,
        protocolVersion: proto, originalState: ["sleep": "1"],
        expectedState: ["sleep": "1"]
    )
}

@Suite("Recovery journal (T019 Core half)")
struct RecoveryTests {
    @Test("corrupt record fails verification and blocks reads")
    func corruption() throws {
        var journal = RecoveryJournal()
        try journal.commit(makeRecord())
        var tampered = try journal.record(for: "s")
        tampered.expectedState = ["sleep": "0"]  // outside write, checksum now stale
        do {
            try tampered.verifyIntegrity()
            Issue.record("expected corruption throw")
        } catch {
            #expect(error == .corrupt("s"))
        }
    }

    @Test("missing journal prevents lookup")
    func missing() throws {
        let journal = RecoveryJournal()
        do {
            _ = try journal.record(for: "nope")
            Issue.record("expected missing throw")
        } catch {
            #expect(error == .missing("nope"))
        }
    }

    @Test("full journal rejects new sessions but keeps existing")
    func full() throws {
        var journal = RecoveryJournal(capacity: 1)
        try journal.commit(makeRecord(session: "s1"))
        do {
            try journal.commit(makeRecord(session: "s2"))
            Issue.record("expected full throw")
        } catch {
            #expect((error as? JournalError) == .full(limit: 1))
        }
        #expect((try? journal.record(for: "s1")) != nil)
    }

    @Test("protocol mismatch invalidates old records")
    func protocolInvalidation() throws {
        var journal = RecoveryJournal(currentProtocol: 2)
        do {
            try journal.commit(makeRecord(proto: 1))
            Issue.record("expected protocol throw")
        } catch {
            #expect((error as? JournalError) == .unsupportedProtocol(have: 1, want: 2))
        }
    }

    @Test("crash point: committed pending record recovers as pending")
    func crashPoint() throws {
        var journal = RecoveryJournal()
        try journal.commit(makeRecord())
        let record = try journal.record(for: "s")
        #expect(record.restoreOutcome == .pending)
        try journal.markRestore(sessionID: "s", outcome: .verified)
        #expect(try journal.record(for: "s").restoreOutcome == .verified)
    }

    @Test("ownership mismatch returns conflict, never a guessed reset")
    func conflict() throws {
        var journal = RecoveryJournal()
        try journal.commit(makeRecord(owner: "uid501"))
        let (outcome, evidence) = journal.recoverOwnedState(
            sessionID: "s", requester: "uid502", dryRun: false
        )
        #expect(outcome == .conflict)
        #expect(evidence["reason"] == "ownerMismatch")
    }

    @Test("unknown session returns unknown with evidence")
    func unknownSession() throws {
        let journal = RecoveryJournal()
        let (outcome, evidence) = journal.recoverOwnedState(
            sessionID: "ghost", requester: "uid501", dryRun: false
        )
        #expect(outcome == .unknown)
        #expect(evidence["reason"] == "journalMissing")
    }

    @Test("dry-run reports restorable without mutating")
    func dryRun() throws {
        var journal = RecoveryJournal()
        try journal.commit(makeRecord())
        let (outcome, _) = journal.recoverOwnedState(
            sessionID: "s", requester: "uid501", dryRun: true
        )
        #expect(outcome == .restorable)
        #expect(try journal.record(for: "s").restoreOutcome == .pending)
    }

    @Test("sleep request follows restoration state")
    func sleepGating() throws {
        #expect(PowerController.sleepRequest(lidState: .closed, restore: .verified) == .request)
        #expect(
            PowerController.sleepRequest(lidState: .closed, restore: .pending)
                == .hold(reason: "restorationPending")
        )
        #expect(
            PowerController.sleepRequest(lidState: .unknown, restore: .verified)
                == .blocked(reason: "blockerUnknown")
        )
        #expect(
            PowerController.sleepRequest(lidState: .closed, restore: .conflict)
                == .blocked(reason: "restorationConflict")
        )
        #expect(PowerController.restorationRequired(.pending) == true)
        #expect(PowerController.restorationRequired(.verified) == false)
    }

    @Test("cpu sustained advisory and optional stop")
    func cpuAdvisory() throws {
        var observer = CPUObserver()
        var evaluation = observer.evaluate(cpuPercent: 95, cpuStopEnabled: false, now: 0)
        #expect(evaluation.advisory == false)
        evaluation = observer.evaluate(cpuPercent: 95, cpuStopEnabled: false, now: 119)
        #expect(evaluation.advisory == false)
        evaluation = observer.evaluate(cpuPercent: 95, cpuStopEnabled: false, now: 120)
        #expect(evaluation == CPUEvaluation(advisory: true, stop: false, reasons: ["cpuSustained"]))
        evaluation = observer.evaluate(cpuPercent: 95, cpuStopEnabled: true, now: 200)
        #expect(evaluation.stop == true)
        evaluation = observer.evaluate(cpuPercent: nil, cpuStopEnabled: true, now: 300)
        #expect(evaluation == CPUEvaluation(advisory: false, stop: false, reasons: ["cpuUnknown"]))
    }
}
