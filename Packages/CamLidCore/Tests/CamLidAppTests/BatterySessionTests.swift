import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Battery preview admission and non-extending cap", .serialized)
@MainActor
struct BatterySessionTests {
    private func health(_ power: PowerSource, battery: Double? = 60) throws -> HealthSnapshot {
        try HealthSnapshot(batteryPercent: battery, powerSource: power, thermalPressure: .nominal,
            lidState: .open, internalDisplayState: .awake)
    }
    private func status(_ app: AppCoordinator) throws -> [String: Any] {
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        return try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
    }
    private func apply(_ object: [String: Any], to app: AppCoordinator) async throws {
        let revision = try #require(status(app)["revision"] as? Int)
        guard case .saved = await app.applySettingsPatchAsync(try ConfigPatch(jsonDictionary: object), expectedRevision: revision) else {
            Issue.record("Expected isolated preference write"); return
        }
    }
    private func session(_ app: AppCoordinator) throws -> [String: Any] {
        try #require(status(app)["session"] as? [String: Any])
    }

    @Test func refusesLowUnknownAndNonOptedInBattery() async throws {
        for battery: Double? in [39, nil, 60] {
            let fixture = QARefinementSupport(); defer { fixture.cleanup() }
            let reading = try health(.battery, battery: battery)
            let app = fixture.makeCoordinator(healthReader: { reading })
            try await apply(["mode": "timed", "chargingOnly": false, "batteryModeAllowed": battery != 60], to: app)
            await app.startPreviewSession()
            #expect(try status(app)["session"] == nil)
            let notice = try #require(app.dashboardData().bannerMessage)
            #expect(!notice.contains("batteryEntryLow") && !notice.contains("notCharging"))
            #expect(try status(app)["powerActuation"] as? Bool == false)
            #expect(await app.flushHistory())
        }
    }

    @Test func infiniteStartsBoundedAndRevocationStopsAtNextEvaluation() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let reading = try health(.battery, battery: 40)
        let app = fixture.makeCoordinator(healthReader: { reading })
        try await apply(["mode": "timed", "timerMinutes": 0, "chargingOnly": false, "batteryModeAllowed": true], to: app)
        await app.startPreviewSession()
        let active = try session(app)
        let start = try #require(active["startedAtMonotonic"] as? Double)
        #expect(try #require(active["capDeadlineMonotonic"] as? Double) == start + 3_600)
        #expect(active["armedClosedLid"] as? Bool == false)
        try await apply(["batteryModeAllowed": false], to: app)
        #expect(try session(app)["latchedSafetyStop"] as? Bool == true)
        #expect((try session(app)["stopReasons"] as? [String])?.contains("notCharging") == true)
        #expect(await app.flushHistory())
    }

    @Test func unplugCapsFromOriginalStartAndNoEditOrACReturnExtendsIt() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        var reading = try health(.ac)
        let app = fixture.makeCoordinator(healthReader: { reading })
        try await apply(["mode": "timed", "timerMinutes": 0, "chargingOnly": false, "batteryModeAllowed": true], to: app)
        await app.startPreviewSession()
        let initial = try session(app)
        #expect(initial["capDeadlineMonotonic"] == nil)
        let start = try #require(initial["startedAtMonotonic"] as? Double)
        reading = try health(.battery)
        app.changeMode(.timed)
        let deadline = try #require(session(app)["capDeadlineMonotonic"] as? Double)
        #expect(deadline == start + 3_600)
        try await apply(["batteryCapMinutes": 120], to: app)
        #expect(try session(app)["capDeadlineMonotonic"] as? Double == deadline)
        reading = try health(.ac)
        app.changeMode(.auto)
        app.changeMode(.timed)
        let revision = try #require(status(app)["revision"] as? Int)
        #expect(app.changeTimerDuration(0, expectedRevision: revision))
        #expect(try session(app)["capDeadlineMonotonic"] as? Double == deadline)
        try await apply(["batteryCapMinutes": 30], to: app)
        #expect(try session(app)["capDeadlineMonotonic"] as? Double == start + 1_800)
        #expect(try status(app)["powerActuation"] as? Bool == false)
        #expect(await app.flushHistory())
    }

    @Test func batteryAdmissionLatchesCeilingBeforeFirstACRefresh() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let battery = try health(.battery)
        let ac = try health(.ac)
        var admitOnBattery = false
        let app = fixture.makeCoordinator(healthReader: {
            if admitOnBattery { admitOnBattery = false; return battery }
            return ac
        })
        try await apply(["mode": "timed", "timerMinutes": 0, "chargingOnly": false, "batteryModeAllowed": true], to: app)
        admitOnBattery = true
        await app.startPreviewSession()
        let active = try session(app)
        let start = try #require(active["startedAtMonotonic"] as? Double)
        let ceiling = start + 3_600
        #expect(active["capDeadlineMonotonic"] as? Double == ceiling)
        let revision = try #require(status(app)["revision"] as? Int)
        #expect(app.changeTimerDuration(0, expectedRevision: revision))
        #expect(try session(app)["capDeadlineMonotonic"] as? Double == ceiling)
        app.changeMode(.manual)
        #expect(try session(app)["capDeadlineMonotonic"] as? Double == ceiling)
        #expect(try status(app)["powerActuation"] as? Bool == false)
        #expect(await app.flushHistory())
    }

    @Test func batteryTimerUsesEffectiveCapInsteadOfClaimingTwoHours() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let reading = try health(.battery, battery: 80)
        let app = fixture.makeCoordinator(healthReader: { reading })
        try await apply(["mode": "timed", "timerMinutes": 120, "chargingOnly": false, "batteryModeAllowed": true], to: app)
        await app.startPreviewSession()
        let active = try session(app)
        let start = try #require(active["startedAtMonotonic"] as? Double)
        let initial = try #require(app.dashboardData().timerMaximumMinutes)
        #expect(initial == 60)
        #expect(app.dashboardData().timerLimitText?.contains("60 min") == true)
        let revision = try #require(status(app)["revision"] as? Int)
        #expect(app.changeTimerDuration(120, expectedRevision: revision))
        let changed = try #require(app.dashboardData().timerMaximumMinutes)
        #expect(changed == 60)
        #expect(try #require(app.dashboardData().timerMinutes) == 60)
        let changedSession = try session(app)
        #expect((changedSession["capDeadlineMonotonic"] as? Double ?? .infinity) <= start + 3_600)
        #expect(await app.flushHistory())
    }

    @Test func acTimerEditActuallyExtendsToTheSelectedDuration() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try await apply(["mode": "timed", "timerMinutes": 60], to: app)
        await app.startPreviewSession()
        let active = try session(app)
        let start = try #require(active["startedAtMonotonic"] as? Double)
        #expect(try #require(app.dashboardData().timerMinutes) == 60)
        let revision = try #require(status(app)["revision"] as? Int)
        #expect(app.changeTimerDuration(120, expectedRevision: revision))
        #expect(try #require(app.dashboardData().timerMinutes) == 120)
        #expect(app.dashboardData().timerMaximumMinutes == 120)
        #expect(app.dashboardData().timerLimitText == nil)
        let changed = try session(app)
        let deadline = try #require(changed["capDeadlineMonotonic"] as? Double)
        #expect(deadline > start + 3_600)
        #expect(deadline <= start + 7_300)
        #expect(await app.flushHistory())
    }

    @Test func settingsAutosaveValidatesNewFieldsAndRetainsFailedIntent() throws {
        var current = try Configuration()
        let editor = SettingsEditor(configuration: current, revision: 1, section: .safety)
        editor.configureAutosave { patch, revision in
            do { current = try current.applying(patch); return .saved(revision: revision + 1) }
            catch { return .failed("Invalid battery setting") }
        }
        editor.setChargingOnly(false)
        editor.batterySessionsAllowed = true
        editor.selectPreset(50, field: .batteryEntry)
        editor.selectPreset(30, field: .batteryCap)
        #expect(current.batteryModeAllowed && !current.chargingOnly)
        #expect(current.batteryEntryPercent == 50 && current.batteryCapMinutes == 30 && !editor.isDirty)
        editor.editNumber("20", field: .batteryEntry); editor.commitNumber(.batteryEntry)
        #expect(editor.errors.contains { $0.field == .batteryEntry })
        #expect(current.batteryEntryPercent == 50 && editor.isDirty)
        editor.cancelNumber(.batteryEntry)
        editor.configureAutosave { _, _ in .failed("Storage refused") }
        editor.setBatteryModeAllowed(false)
        #expect(!editor.draft.batteryModeAllowed && editor.isDirty && current.batteryModeAllowed)
        #expect(NumericChoice.label(50, field: .batteryEntry) == "50%")
        editor.discard()
    }

    @Test func theClosedLidSwitchSavesTheOptInAndRestoresItWhenSavingFails() throws {
        var current = try Configuration()
        let editor = SettingsEditor(configuration: current, revision: 1, section: .safety)
        editor.configureAutosave { patch, revision in
            do { current = try current.applying(patch); return .saved(revision: revision + 1) }
            catch { return .failed("Invalid setting") }
        }
        editor.setClosedLidOptIn(true)
        #expect(current.closedLidOptIn && editor.draft.closedLidOptIn && !editor.isDirty)
        editor.configureAutosave { _, _ in .failed("Storage refused") }
        editor.setClosedLidOptIn(false)
        #expect(current.closedLidOptIn && editor.isDirty)
        editor.discard()
        #expect(editor.draft.closedLidOptIn)
    }
}
