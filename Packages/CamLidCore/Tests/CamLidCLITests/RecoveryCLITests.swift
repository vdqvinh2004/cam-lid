import Foundation
import Testing
import CamLidCLI

@testable import CamLidCore

// Recovery CLI tests (T024): denied authorization, app unavailable,
// conflict/unknown outcomes, dry-run-no-mutation.

struct ThrowingChannel: IPCChannel, Sendable {
    let error: IPCError
    func send(command: AllowlistedCommand, payload: Data) throws -> Data { throw error }
}

func journalWithOwnedSession(owner: String = "local-user") throws -> RecoveryJournal {
    var journal = RecoveryJournal()
    try journal.commit(try RecoveryRecord(
        journalRevision: 1, sessionID: "s1", ownerIdentity: owner,
        originalState: ["sleep": "on"], expectedState: ["sleep": "on"]))
    return journal
}

@Suite("Recovery CLI (T024)")
struct RecoveryCLITests {
    @Test("denied authorization refuses without mutation")
    func deniedAuthorization() throws {
        let before = try journalWithOwnedSession()
        var command = RecoveryCommand(
            journal: before, ownerIdentity: "local-user", authorized: false)
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .conflict)
        #expect(diagnosis.exitCode == 3)
        #expect(diagnosis.evidence["reason"] == "authDenied")
        let after = try command.journal.record(for: "s1")
        #expect(after == (try before.record(for: "s1")))
    }

    @Test("unavailable channel on apply reports unresolved exit 5")
    func appUnavailable() throws {
        let before = try journalWithOwnedSession()
        var command = RecoveryCommand(
            journal: before, ownerIdentity: "local-user",
            channel: ThrowingChannel(error: .unavailable))
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .unresolved)
        #expect(diagnosis.exitCode == 5)
        #expect(diagnosis.evidence["reason"] == "serviceUnavailable")
        #expect(try command.journal.record(for: "s1") == (try before.record(for: "s1")))
    }

    @Test("channel denial on apply reports conflict exit 3")
    func channelDenial() throws {
        var command = RecoveryCommand(
            journal: try journalWithOwnedSession(), ownerIdentity: "local-user",
            channel: ThrowingChannel(error: .unauthorized))
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .conflict)
        #expect(diagnosis.exitCode == 3)
    }

    @Test("owner mismatch is conflict exit 3")
    func ownerMismatchConflict() throws {
        var command = RecoveryCommand(
            journal: try journalWithOwnedSession(owner: "other-user"),
            ownerIdentity: "local-user")
        let dry = command.run(sessionID: "s1", dryRun: true, lidState: .open)
        #expect(dry.outcome == .conflict)
        #expect(dry.exitCode == 3)
        let applied = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(applied.outcome == .conflict)
        #expect(applied.exitCode == 3)
    }

    @Test("missing session is unknown exit 5")
    func missingSessionUnknown() throws {
        var command = RecoveryCommand(
            journal: try journalWithOwnedSession(), ownerIdentity: "local-user")
        let diagnosis = command.run(sessionID: "nope", dryRun: true, lidState: .open)
        #expect(diagnosis.outcome == .unknown)
        #expect(diagnosis.exitCode == 5)
    }

    @Test("dry-run never mutates the journal")
    func dryRunNoMutation() throws {
        let before = try journalWithOwnedSession()
        var command = RecoveryCommand(journal: before, ownerIdentity: "local-user")
        let diagnosis = command.run(sessionID: "s1", dryRun: true, lidState: .open)
        #expect(diagnosis.outcome == .restorable)
        #expect(diagnosis.exitCode == 0)
        #expect(diagnosis.evidence["mode"] == "dryRun")
        #expect(command.journal.count == before.count)
        #expect(try command.journal.record(for: "s1") == (try before.record(for: "s1")))
    }

    @Test("apply marks verified only with confirming restore readback")
    func applyMarksVerified() throws {
        var command = RecoveryCommand(
            journal: try journalWithOwnedSession(), ownerIdentity: "local-user",
            recoveryService: InMemoryRecoveryService(shouldVerify: true))
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .verified)
        #expect(diagnosis.exitCode == 0)
        #expect(diagnosis.evidence["sleep"] == "request")
        #expect(try command.journal.record(for: "s1").restoreOutcome == .verified)
    }

    @Test("apply without a recovery service stays unresolved and unmarked")
    func applyWithoutServiceUnresolved() throws {
        let before = try journalWithOwnedSession()
        var command = RecoveryCommand(journal: before, ownerIdentity: "local-user")
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .unresolved)
        #expect(diagnosis.exitCode == 5)
        #expect(diagnosis.evidence["reason"] == "serviceUnavailable")
        #expect(try command.journal.record(for: "s1").restoreOutcome == .pending)
    }
}
