import AppKit
import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// A permission the test can change, so the notification tests need no system prompt.
@MainActor
private final class FakePermission {
    var value = "notDetermined"
}

/// The write and read commands the other agent suites do not reach. Each runs through the app's own handler, on the test
/// fixtures, which are QA copies: nothing reaches the owner's data, the network, a login item or the notification centre,
/// and the commands that a QA copy refuses are checked as refused.
@MainActor
@Suite("Agent writes and reads", .serialized)
struct AgentWritesTests {
    private func object(_ result: CLIResult) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
    }

    private func operate(_ app: AppCoordinator, _ name: String, _ positionals: [String] = [],
                         _ flags: [String: String] = [:]) async throws -> CLIResult {
        let request = OperateRequest(name: name, options: CLIOptions(flags: flags, positionals: positionals))
        return await app.operate(try JSONEncoder().encode(request))
    }

    private func status(_ app: AppCoordinator) throws -> [String: Any] {
        try object(try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data())))
    }

    /// One Auto session started and stopped, so the history has records to read.
    private func runAutoSession(_ app: AppCoordinator) async throws {
        _ = await app.startFromControl(try JSONEncoder().encode(CLIOptions(flags: ["mode": "auto"])))
        app.menuBarStopProtection()
    }

    /// The control socket lives in the fixture's root, which the control server needs to exist, as the integration suites set it up.
    private func makeRoot(_ fixture: QARefinementSupport) throws {
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    /// Runs `camlid` against the app over its control socket, as an agent would. The call waits off the main actor.
    private func camlid(_ argv: [String], _ channel: LocalControlChannel) async -> CLIResult {
        await Task.detached { Commands.runWithRealIO(argv: argv, channel: channel) }.value
    }

    @Test func welcomeIsFinishedOnceAndStaysFinished() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        #expect(try object(try await operate(app, "welcome complete"))["changed"] as? Bool == true)
        #expect(try object(try await operate(app, "welcome complete"))["changed"] as? Bool == false)
        #expect(try object(try await operate(app, "welcome status"))["done"] as? Bool == true)
    }

    @Test func notificationsAreRefusedWhereMacOSCannotAsk() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let refused = try await operate(app, "notifications request")
        #expect(refused.exitCode == 3)
        #expect(try object(refused)["reason"] as? String == "notificationsUnavailable")
    }

    @Test func aDecidedNotificationPermissionIsNotAskedAgain() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let answer = FakePermission()
        answer.value = "authorized"
        let notifications = OutcomeNotifications(supported: true, readPermission: { answer.value },
            requestPermission: { answer.value = "authorized" }, deliver: { _ in })
        let app = fixture.makeCoordinator(outcomeNotifications: notifications)
        await notifications.refresh()
        let decided = try object(try await operate(app, "notifications request"))
        #expect(decided["changed"] as? Bool == false)
        #expect(decided["permission"] as? String == "authorized")
    }

    @Test func anUndecidedPermissionIsAskedOnceAndThenStands() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let answer = FakePermission()
        let notifications = OutcomeNotifications(supported: true, readPermission: { answer.value },
            requestPermission: { answer.value = "authorized" }, deliver: { _ in })
        let app = fixture.makeCoordinator(outcomeNotifications: notifications)
        await notifications.refresh()
        #expect(try object(try await operate(app, "notifications request"))["changed"] as? Bool == true)
        try await Task.sleep(nanoseconds: 100_000_000)
        await notifications.refresh()
        let again = try object(try await operate(app, "notifications request"))
        #expect(again["changed"] as? Bool == false)
        #expect(again["permission"] as? String == "authorized")
    }

    @Test func aQACopyDoesNotRegisterALoginItem() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let refused = try await operate(app, "login apply")
        #expect(refused.exitCode == 4)
        #expect(try object(refused)["reason"] as? String == "loginItemFailed")
    }

    @Test func aQACopyDoesNotWriteTheSharedSkillFile() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let install = try await operate(app, "skill install")
        #expect(install.exitCode == 3)
        #expect(try object(install)["reason"] as? String == "qaCopy")
        let remove = try await operate(app, "skill remove")
        #expect(remove.exitCode == 3)
        #expect(try object(remove)["reason"] as? String == "qaCopy")
        #expect(try object(try await operate(app, "skill status"))["installed"] as? Bool == false)
    }

    @Test func aQACopyDoesNotCheckOrInstallUpdates() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let check = try await operate(app, "update check")
        #expect(check.exitCode == 3)
        #expect(try object(check)["reason"] as? String == "qaCopy")
        let install = try await operate(app, "update install")
        #expect(install.exitCode == 3)
        #expect(try object(install)["reason"] as? String == "qaCopy")
    }

    @Test func automaticUpdateChecksChangeOnlyWhenTheyDiffer() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        defer { _ = app }
        let off = try object(try await operate(app, "update auto", ["off"]))
        #expect(off["automaticChecks"] as? Bool == false)
        #expect(try object(try await operate(app, "update auto", ["off"]))["changed"] as? Bool == false)
        let on = try object(try await operate(app, "update auto", ["on"]))
        #expect(on["changed"] as? Bool == true)
        #expect(on["automaticChecks"] as? Bool == true)
        _ = try await operate(app, "update auto", ["off"])
    }

    @Test func theUntestedMacAllowanceIsSetAndWithdrawnByItsOwnFlags() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(systemIdentity: { (model: "Mac16,1", osBuild: "25A100") })
        let confirmed = try object(try await operate(app, "closed-lid acknowledge-untested", [], ["confirm": "true"]))
        #expect(confirmed["acknowledged"] as? Bool == true)
        #expect(confirmed["changed"] as? Bool == true)
        #expect(try object(try await operate(app, "closed-lid acknowledge-untested", [], ["confirm": "true"]))["changed"] as? Bool == false)
        let revoked = try object(try await operate(app, "closed-lid acknowledge-untested", [], ["revoke": "true"]))
        #expect(revoked["acknowledged"] as? Bool == false)
        #expect(revoked["changed"] as? Bool == true)
    }

    @Test func theUntestedMacAllowanceIsRefusedWhereTheMacCannotBeIdentified() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let refused = try await operate(app, "closed-lid acknowledge-untested", [], ["confirm": "true"])
        #expect(refused.exitCode == 3)
        #expect(try object(refused)["reason"] as? String == "macIdentityUnavailable")
        #expect(app.untestedAcknowledgementStored == false)
    }

    @Test func theGeneralAudioHoldChangesOnlyWhenItDiffers() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let on = try object(try await operate(app, "audio-hold", ["on"]))
        #expect(on["changed"] as? Bool == true)
        #expect(on["enabled"] as? Bool == true)
        #expect(try object(try await operate(app, "audio-hold", ["on"]))["changed"] as? Bool == false)
        #expect(try object(try await operate(app, "audio-hold", ["off"]))["changed"] as? Bool == true)
        #expect(try await operate(app, "audio-hold", ["maybe"]).exitCode == 2)
    }

    @Test func logsDeleteRefusesAnUnknownSessionAndClearsTheHistoryOnce() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try await runAutoSession(app)
        let unknown = try await operate(app, "logs delete", [], ["session": "session-0000000000000000", "confirm": "true"])
        #expect(unknown.exitCode == 2)
        #expect(try object(unknown)["reason"] as? String == "unknownSession")
        let cleared = try object(try await operate(app, "logs delete", [], ["all": "true", "confirm": "true"]))
        #expect(cleared["changed"] as? Bool == true)
        #expect(cleared["receipt"] != nil)
        #expect(try object(try await operate(app, "logs delete", [], ["all": "true", "confirm": "true"]))["changed"] as? Bool == false)
    }

    @Test func logsListPagesFiltersAndSearchesLikeTheActivityWindow() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try await runAutoSession(app)
        try await runAutoSession(app)
        let page = try object(try await operate(app, "logs list", [], ["limit": "1"]))
        let first = try #require(page["records"] as? [[String: Any]])
        #expect(first.count == 1)
        let cursor = try #require(page["nextCursor"] as? String)
        let next = try object(try await operate(app, "logs list", [], ["limit": "1", "cursor": cursor]))
        let second = try #require(next["records"] as? [[String: Any]])
        #expect(second.first?["id"] as? String != first.first?["id"] as? String)
        let enrolment = try object(try await operate(app, "logs list", [], ["category": "enrollment"]))
        let enrolled = try #require(enrolment["records"] as? [[String: Any]])
        #expect(!enrolled.isEmpty && enrolled.allSatisfy { $0["category"] as? String == "enrollment" })
        let searched = try object(try await operate(app, "logs list", [], ["query": "sessionStarted"]))
        let hits = try #require(searched["records"] as? [[String: Any]])
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { ($0["reasonCodes"] as? [String])?.contains("sessionStarted") == true })
        let bad = try await operate(app, "logs list", [], ["cursor": "not-a-record"])
        #expect(bad.exitCode == 2)
        #expect(try object(bad)["reason"] as? String == "invalidCursor")
    }

    @Test func statusCarriesTheFieldsTheCLIDocuments() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let fields = try status(app)
        for key in ["version", "language", "music", "audioHold", "skill", "welcome"] {
            #expect(fields[key] != nil, "status lacks \(key)")
        }
        #expect((fields["music"] as? [[String: Any]])?.count == MusicSource.allCases.count)
        let updates = try #require(fields["updates"] as? [String: Any])
        #expect(updates["automaticChecks"] as? Bool != nil)
    }

    @Test func agentsListNamesEachProviderWithItsState() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let fields = try object(try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.agentsList, payload: Data())))
        let agents = try #require(fields["agents"] as? [[String: Any]])
        #expect(agents.count == AgentBadgeState.providers.count)
        #expect(agents.allSatisfy { $0["provider"] != nil && $0["enabled"] != nil && $0["observedState"] != nil })
    }

    @Test func versionCarriesTheAppsVersionBuildAndCopyright() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let fields = try object(try await operate(app, "version"))
        let appFields = try #require(fields["app"] as? [String: Any])
        #expect(appFields["version"] != nil && appFields["build"] != nil && appFields["copyright"] != nil)
    }

    @Test func openNamesOnlyTheWindowsItKnows() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let nowhere = try await operate(app, "open", ["nowhere"])
        #expect(nowhere.exitCode == 2)
        #expect(try object(nowhere)["reason"] as? String == "unknownWindow")
        let missing = try await operate(app, "open")
        #expect(missing.exitCode == 2)
        #expect(try object(missing)["reason"] as? String == "invalidOptions")
    }

    @Test func configSetWritesNothingWhenTheValueAlreadyStands() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try makeRoot(fixture)
        app.startControlService()
        defer { app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let channel = LocalControlChannel(directory: fixture.root.appendingPathComponent("control"))
        let first = await camlid(["config", "set", "runCapMinutes", "75"], channel)
        #expect(first.exitCode == 0)
        let revision = app.revision
        let same = await camlid(["config", "set", "runCapMinutes", "75"], channel)
        #expect(same.exitCode == 0)
        #expect(try object(same)["changed"] as? Bool == false)
        #expect(app.revision == revision)
        let invalid = await camlid(["config", "set", "runCapMinutes", "lots"], channel)
        #expect(invalid.exitCode == 2)
    }

    @Test func watchedProgramsTurnOnAndOffThroughTheControlChannel() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try makeRoot(fixture)
        // Watched programs cannot be system binaries, so the test watches an executable it writes into its own root.
        let tool = fixture.root.appendingPathComponent("qa-watch-tool")
        try "#!/bin/sh\nexit 0\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        app.startControlService()
        defer { app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let channel = LocalControlChannel(directory: fixture.root.appendingPathComponent("control"))
        let added = await camlid(["watch", "add", "--executable", tool.path, "--label", "QA"], channel)
        #expect(added.exitCode == 0)
        let id = try #require(try object(added)["ruleID"] as? String)
        let off = try object(await camlid(["watch", "disable", id], channel))
        #expect(off["changed"] as? Bool == true)
        #expect(off["enabled"] as? Bool == false)
        #expect(try object(await camlid(["watch", "disable", id], channel))["changed"] as? Bool == false)
        let on = try object(await camlid(["watch", "enable", id], channel))
        #expect(on["changed"] as? Bool == true)
        #expect(on["enabled"] as? Bool == true)
        let unknown = await camlid(["watch", "enable", UUID().uuidString], channel)
        #expect(unknown.exitCode == 2)
        #expect(try object(unknown)["reason"] as? String == "ruleNotFound")
    }
}
