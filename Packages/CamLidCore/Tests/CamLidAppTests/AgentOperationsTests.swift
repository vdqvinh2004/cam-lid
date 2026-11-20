import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// The app's side of the agent contract: `start` and the session commands change only what was asked, a repeated request
/// changes nothing, and a refused request saves nothing. The parsing and the reasons are tested in AgentCLITests.
@MainActor
@Suite("Agent operations", .serialized)
struct AgentOperationsTests {
    private func object(_ result: CLIResult) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
    }

    private func start(_ app: AppCoordinator, _ flags: [String: String]) async throws -> CLIResult {
        await app.startFromControl(try JSONEncoder().encode(CLIOptions(flags: flags)))
    }

    private func operate(_ app: AppCoordinator, _ name: String, _ positionals: [String] = [],
                         _ flags: [String: String] = [:]) async throws -> CLIResult {
        let request = OperateRequest(name: name, options: CLIOptions(flags: flags, positionals: positionals))
        return await app.operate(try JSONEncoder().encode(request))
    }

    private func save(_ app: AppCoordinator, _ values: [String: Any]) async throws {
        let patch = try ConfigPatch(jsonDictionary: values)
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: app.revision) else {
            Issue.record("The settings \(values) were not saved")
            return
        }
    }

    @Test func aStartAsksForAutoAndAgainChangesNothing() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let first = try await start(app, [:])
        #expect(first.exitCode == 0)
        #expect(try object(first)["outcome"] as? String == "started")
        #expect(try object(first)["changed"] as? Bool == true)
        #expect(try object(first)["mode"] as? String == "auto")
        let again = try await start(app, ["mode": "auto"])
        #expect(again.exitCode == 0)
        #expect(try object(again)["outcome"] as? String == "alreadyRunning")
        #expect(try object(again)["changed"] as? Bool == false)
        #expect(try object(again)["powerActuation"] as? Bool == false)
        app.menuBarStopProtection()
    }

    @Test func aDifferentModeIsRefusedUntilReplaceSwitchesIt() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        _ = try await start(app, ["mode": "auto"])
        let refused = try await start(app, ["mode": "timed", "duration": "45m"])
        #expect(refused.exitCode == 3)
        #expect(try object(refused)["reason"] as? String == "sessionAlreadyActive")
        #expect(app.session?.requestedMode == .auto)
        let replaced = try await start(app, ["mode": "timed", "duration": "45m", "replace": "true"])
        let fields = try object(replaced)
        #expect(replaced.exitCode == 0)
        #expect(fields["outcome"] as? String == "replaced")
        #expect(fields["durationSeconds"] as? Int == 2_700)
        #expect((fields["replacedSessionPseudonym"] as? String)?.hasPrefix("session-") == true)
        #expect(app.session?.requestedMode == .timed)
        app.menuBarStopProtection()
    }

    @Test func aTimerChangeOnTheRunningTimedSessionIsASwitchOfItsTimer() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        _ = try await start(app, ["mode": "timed", "duration": "45m"])
        let same = try object(try await start(app, ["mode": "timed", "duration": "45m"]))
        #expect(same["outcome"] as? String == "alreadyRunning")
        let retimed = try object(try await start(app, ["mode": "timed", "duration": "infinite", "replace": "true"]))
        #expect(retimed["outcome"] as? String == "timerChanged")
        #expect(retimed["changed"] as? Bool == true)
        #expect(retimed["durationSeconds"] as? Int == 0)
        app.menuBarStopProtection()
    }

    @Test func saveModeChangesTheSavedModeOnlyOnce() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let saved = try object(try await start(app, ["mode": "timed", "duration": "30m", "save-mode": "true"]))
        #expect(saved["savedMode"] as? Bool == true)
        #expect(app.config.mode == .timed)
        app.menuBarStopProtection()
        let again = try object(try await start(app, ["mode": "timed", "duration": "30m", "save-mode": "true"]))
        #expect(again["savedMode"] as? Bool == false)
        app.menuBarStopProtection()
    }

    @Test func aRefusedStartSavesNothing() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let low = try HealthSnapshot(batteryPercent: 10, powerSource: .battery, thermalPressure: .nominal,
            lidState: .open, internalDisplayState: .awake)
        let app = fixture.makeCoordinator(healthReader: { low })
        try await save(app, ["chargingOnly": false, "batteryModeAllowed": true, "batteryEntryPercent": 45])
        let before = app.config.mode
        let refused = try await start(app, ["mode": "timed", "duration": "45m", "save-mode": "true"])
        #expect(refused.exitCode == 3)
        #expect(try object(refused)["reason"] as? String == "batteryEntryLow")
        #expect(app.config.mode == before)
        #expect(app.session == nil)
    }

    @Test func closedLidNeedsTheSavedOptInAndSaysSo() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let refused = try await start(app, ["mode": "auto", "closed-lid": "true"])
        #expect(refused.exitCode == 3)
        #expect(try object(refused)["reason"] as? String == "closedLidOff")
        #expect(app.session == nil)
    }

    @Test func sessionDurationChangesTheRunningTimedSessionOnlyWhenItDiffers() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try await save(app, ["mode": "timed", "timerMinutes": 60])
        await app.startPreviewSession()
        let changed = try object(try await operate(app, "session duration", ["45m"], ["expectedRevision": String(app.revision)]))
        #expect(changed["changed"] as? Bool == true)
        #expect(changed["durationSeconds"] as? Int == 2_700)
        let same = try object(try await operate(app, "session duration", ["45m"]))
        #expect(same["changed"] as? Bool == false)
        let bare = try await operate(app, "session duration", ["45"])
        #expect(bare.exitCode == 2)
        #expect(try object(bare)["reason"] as? String == "durationUnitRequired")
        let stale = try await operate(app, "session duration", ["30m"], ["expectedRevision": "1"])
        #expect(stale.exitCode == 2)
        #expect(try object(stale)["reason"] as? String == "revisionConflict")
        app.menuBarStopProtection()
    }

    @Test func sessionSleepDelayNeedsAnAutoSession() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try await save(app, ["mode": "timed", "timerMinutes": 60])
        await app.startPreviewSession()
        let wrongMode = try await operate(app, "session sleep-delay", ["9m"])
        #expect(wrongMode.exitCode == 3)
        #expect(try object(wrongMode)["reason"] as? String == "noAutoSession")
        app.menuBarStopProtection()
        try await save(app, ["mode": "auto"])
        await app.startPreviewSession()
        let set = try object(try await operate(app, "session sleep-delay", ["9m"]))
        #expect(set["changed"] as? Bool == true)
        #expect(set["sleepDelayMinutes"] as? Int == 9)
        let same = try object(try await operate(app, "session sleep-delay", ["9m"]))
        #expect(same["changed"] as? Bool == false)
        app.menuBarStopProtection()
    }

    @Test func readsAnswerFromTheAppAndChangeNothing() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        for name in ["music list", "language get", "skill status", "update status", "welcome status", "version"] {
            let result = try await operate(app, name)
            #expect(result.exitCode == 0, "\(name) should answer")
            #expect(!result.json.contains("unknownCommand"), "\(name) should be handled")
        }
        #expect(app.session == nil)
    }

    @Test func agentEnrolmentChangesOnlyTheNamedProvider() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let provider = try #require(AgentBadgeState.providers.first)
        _ = try await operate(app, "agents enable", [provider])
        let again = try object(try await operate(app, "agents enable", [provider]))
        #expect(again["changed"] as? Bool == false)
        let disabled = try object(try await operate(app, "agents disable", [provider]))
        #expect(disabled["changed"] as? Bool == true)
        #expect(app.config.adapterEnrollment.contains(provider) == false)
    }

    @Test func languageAndMusicWritesChangeOnlyWhatDiffers() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        _ = try await operate(app, "language set", ["english"])
        let sameLanguage = try object(try await operate(app, "language set", ["english"]))
        #expect(sameLanguage["changed"] as? Bool == false)
        #expect(try object(try await operate(app, "language get"))["language"] as? String == "english")
        _ = try await operate(app, "music set", ["chromium", "on"])
        let sameMusic = try object(try await operate(app, "music set", ["chromium", "on"]))
        #expect(sameMusic["changed"] as? Bool == false)
        #expect(sameMusic["enabled"] as? Bool == true)
        let unknown = try await operate(app, "music set", ["winamp", "on"])
        #expect(unknown.exitCode == 2)
        #expect(try object(unknown)["reason"] as? String == "unknownSource")
    }

    @Test func closedLidAcknowledgementWithoutConfirmOrRevokeRecordsNothing() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let refused = try await operate(app, "closed-lid acknowledge-untested")
        #expect(refused.exitCode == 2)
        #expect(try object(refused)["reason"] as? String == "confirmationRequired")
        let hint = try object(refused)["hint"] as? String
        #expect(hint?.contains("--confirm") == true)
        #expect(hint?.contains("--revoke") == true)
    }

    @Test func logsListShowsRedactedRecordsWithoutRawSessionIDs() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        _ = try await start(app, ["mode": "auto"])
        app.menuBarStopProtection()
        let listed = try object(try await operate(app, "logs list", [], ["limit": "20"]))
        let records = try #require(listed["records"] as? [[String: Any]])
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0["sessionID"] == nil })
        #expect(records.contains { ($0["sessionPseudonym"] as? String)?.hasPrefix("session-") == true })
    }

    @Test func aNameTheAppDoesNotKnowIsRefusedNotGuessed() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let result = try await operate(app, "no such command")
        #expect(result.exitCode == 2)
        #expect(try object(result)["reason"] as? String == "unknownCommand")
    }
}
