import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("UI simplicity truth", .serialized)
struct UISimplicityTests {
    @Test func autoHidesTimerCountdownWithoutReservingSpace() {
        let auto = DashboardData(mode: .auto, state: .ready, reasonText: "", capRemainingSeconds: 900, stopEnabled: true)
        let timed = DashboardData(mode: .timed, state: .ready, reasonText: "", capRemainingSeconds: 900, stopEnabled: true)
        let infinite = DashboardData(mode: .timed, state: .ready, reasonText: "", stopEnabled: true)
        #expect(auto.timerRemainingSeconds == nil)
        #expect(timed.timerRemainingSeconds == 900)
        #expect(infinite.timerRemainingSeconds == nil)
    }
    @Test @MainActor func settingsAndUtilitySizingRemainIndependentOfLiveSessions() throws {
        let configuration = try Configuration()
        let editor = SettingsEditor(configuration: configuration, revision: 1)
        #expect(!editor.isDirty && editor.draft.mode == configuration.mode)
        editor.configureAutosave { _, revision in .saved(revision: revision + 1) }
        editor.setMode(.manual)
        #expect(editor.draft.runCapMinutes == configuration.runCapMinutes)
        editor.setMode(.timed)
        editor.selectPreset(30, field: .runCap)
        #expect(editor.draft.mode == .timed && editor.draft.runCapMinutes == 30)
        #expect(!editor.isDirty)
        #expect(ActivityLogView.preferredHeight(recordCount: 0, hasError: false) < ActivityLogView.preferredHeight(recordCount: 6, hasError: false))
        #expect(ActivityLogView.preferredHeight(recordCount: 100_000, hasError: true) <= 480)
        let unavailable = UpdatesView(snapshot: UpdateSnapshot(phase: .unavailable, reason: "noCompatibleUpdate"), canCheck: false, onCheck: {})
        let checking = UpdatesView(snapshot: UpdateSnapshot(phase: .checking, reason: "checkingReleases"), canCheck: false, onCheck: {})
        #expect(unavailable.preferredHeight < checking.preferredHeight)
        #expect(unavailable.preferredHeight >= 110)
        #expect(Set(OnboardingPage.allCases.map(\.preferredHeight)).count == 1)
    }
    @Test @MainActor func infiniteChoiceSurvivesAutoAndMenusHideStopWhenIdle() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let menu = MenuBarController(); menu.actions = app
        #expect(menu.buildMenu().items.first { $0.tag == 1 }?.title == "Auto")
        #expect(menu.buildMenu().items.first { $0.tag == 2 }?.isHidden == true)
        var patch = ConfigPatch(); patch.timerMinutes = 0
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else { Issue.record("Could not save Infinite"); return }
        await app.activateDashboardMode(.auto, expectedRevision: 2)
        await app.activateDashboardMode(.auto, expectedRevision: 3)
        await app.activateDashboardMode(.timed, expectedRevision: 3)
        func status() throws -> [String: Any] {
            let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
            return try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        }
        let infinite = try #require(status()["session"] as? [String: Any])
        #expect(infinite["capDeadlineMonotonic"] == nil)
        #expect(menu.buildMenu().items.first { $0.tag == 2 }?.isHidden == false)
        await app.activateDashboardMode(.auto, expectedRevision: 4)
        let bounded = try #require(status()["session"] as? [String: Any])
        #expect(bounded["id"] as? String == infinite["id"] as? String)
        #expect((bounded["capDeadlineMonotonic"] as? Double ?? 0) == (infinite["startedAtMonotonic"] as? Double ?? 0) + 7200)
        await app.activateDashboardMode(.timed, expectedRevision: 5)
        let unlimitedAgain = try #require(status()["session"] as? [String: Any])
        #expect(unlimitedAgain["id"] as? String == infinite["id"] as? String)
        #expect(unlimitedAgain["capDeadlineMonotonic"] == nil)
        await app.activateDashboardMode(.timed, expectedRevision: 6)
        var finite = ConfigPatch(); finite.timerMinutes = 5
        guard case .saved = await app.applySettingsPatchAsync(finite, expectedRevision: 6) else { Issue.record("Could not save finite timer"); return }
        await app.activateDashboardMode(.auto, expectedRevision: 7)
        let auto = try #require(status()["session"] as? [String: Any])
        await app.activateDashboardMode(.timed, expectedRevision: 8)
        let shortened = try #require(status()["session"] as? [String: Any])
        #expect(shortened["id"] as? String == auto["id"] as? String)
        #expect((shortened["capDeadlineMonotonic"] as? Double ?? 0) == (auto["startedAtMonotonic"] as? Double ?? 0) + 300)
        // Owner-approved cleanup (2026-11-01): three panes.
        #expect(SettingsSection.allCases.map(\.title) == ["General", "Agents", "Closed Lid"])
    }
    @Test @MainActor func dashboardModesStartSwitchAndToggleWithoutResettingCap() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        func status() throws -> [String: Any] {
            let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
            return try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        }
        await app.activateDashboardMode(.timed, expectedRevision: 1)
        let first = try #require(status()["session"] as? [String: Any])
        await app.activateDashboardMode(.auto, expectedRevision: 2)
        let switched = try #require(status()["session"] as? [String: Any])
        #expect(switched["requestedMode"] as? String == "auto")
        #expect(switched["id"] as? String == first["id"] as? String)
        #expect(switched["capDeadlineMonotonic"] as? Double == first["capDeadlineMonotonic"] as? Double)
        await app.activateDashboardMode(.auto, expectedRevision: 3)
        #expect(try status()["session"] == nil)
        await app.activateDashboardMode(.manual, expectedRevision: 3)
        let noTimer = try #require(status()["session"] as? [String: Any])
        #expect(noTimer["requestedMode"] as? String == "manual")
        #expect(noTimer["capDeadlineMonotonic"] == nil)
        await app.activateDashboardMode(.off, expectedRevision: 4)
        #expect(try status()["session"] == nil)
        await app.activateDashboardMode(.manual, expectedRevision: 4)
        #expect(try status()["session"] != nil)
        #expect(try status()["powerActuation"] as? Bool == false)
    }

    @Test @MainActor func rejectedDashboardModeCannotStartSession() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(failingWrites: true)
        await app.activateDashboardMode(.timed, expectedRevision: 1)
        #expect(!app.menuBarCanStop)
        let stale = QARefinementSupport(); defer { stale.cleanup() }
        let other = stale.makeCoordinator()
        await other.activateDashboardMode(.auto, expectedRevision: 0)
        #expect(!other.menuBarCanStop)
    }

    @Test func missingAndStaleMetricsNeverLookHealthy() throws {
        let missing = DashboardMetric.from(nil)
        #expect(missing.count == 4 && missing.allSatisfy { $0.value == "Unknown" })
        let health = try HealthSnapshot(batteryPercent: 42.4, powerSource: .battery,
            thermalPressure: .nominal, cpuPercent: 18.3, lidState: .open)
        let fresh = DashboardMetric.from(health)
        #expect(fresh.first { $0.id == "battery" }?.value == "42%")
        #expect(fresh.first { $0.id == "cpu" }?.value == "18%")
        #expect(fresh.first { $0.id == "thermal" }?.value == "Normal")
        #expect(!fresh.contains { $0.id == "temperature" })
        #expect(DashboardMetric.from(health, isStale: true).allSatisfy { $0.value == "Unknown" })
        #expect(health.cpuPercent == 18.3)
    }

    @Test func qualifiedTemperatureDoesNotReplacePressureAndStaleLidIsUnknown() throws {
        let temperature = TemperatureObservation(valueCelsius: 53.26, sensorID: "fixture-soc",
            displayName: "SoC", source: "qualified-test", sampledAtMonotonic: 100,
            availability: "available", reasonCode: nil)
        let health = try HealthSnapshot(thermalPressure: .critical,
            lid: LidObservation(state: .closed, sampledAtMonotonic: 100).projected(now: 110), temperature: temperature)
        let metrics = DashboardMetric.from(health)
        #expect(metrics.first { $0.id == "thermal" }?.value == "Critical")
        #expect(metrics.first { $0.id == "temperature" }?.value == "53.3°C")
        #expect(metrics.first { $0.id == "lid" }?.value == "Unknown")
        #expect(metrics.first { $0.id == "temperature" }?.detail.contains("SoC") == true)
    }

    @Test func enrollmentSelectionDoesNotInventWork() throws {
        let work = try AgentTask(id: "codex/run", sessionID: "s", runID: "run",
            state: .working, evidenceKind: .lifecycle, confidence: .exact)
        #expect(AgentBadgeState(provider: "codex", enabled: false, tasks: [work]).compactDetail.contains("Active"))
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: []).compactDetail == "Not detected")
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1).observedState == "Unknown")
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: [work]).compactDetail.contains("Active"))
    }

    @Test func eventTitlesAndSearchKeepRawReasons() throws {
        let event = try StoredTransition(stateRevision: 0, category: .configuration,
            previousState: .off, newState: .ready, reasonCodes: ["configApplied"])
        #expect(ActivityPresentation.title(event) == "Settings updated")
        #expect(ActivityFilter(query: "settings updated").matches(event))
        #expect(ActivityFilter(query: "configApplied").matches(event))
        #expect(!ActivityFilter(reasonCode: "agentEvent").matches(event))
        let transition = try StoredTransition(stateRevision: 1, category: .stateTransition,
            previousState: .ready, newState: .safetyStopped, reasonCodes: ["batteryFloor"])
        #expect(ActivityPresentation.title(transition).contains("→"))
    }

    @Test @MainActor func offStartCannotSelectModeOrCreateSession() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.mode = .off
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else {
            Issue.record("Could not save Off"); return
        }
        #expect(app.menuBarCanStart) // Auto menu can start from the saved Off state.
        await app.startPreviewSession()
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let status = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        #expect(status["session"] == nil)
        #expect(status["mode"] as? String == "off")
        #expect(status["powerActuation"] as? Bool == false)
        #expect(await app.flushHistory())
        let events = FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load()
        #expect(!events.contains { $0.reasonCodes.contains("sessionStarted") })
    }

    @Test @MainActor func offModeSettingsEventStaysOffInHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-ui-test-" + UUID().uuidString)
        let suite = "CamLidTest." + root.lastPathComponent
        let prefs = try #require(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let app = AppCoordinator(historyDirectory: root, controlDirectory: root.appendingPathComponent("control"), preferences: prefs)
        var off = ConfigPatch(); off.mode = .off
        guard case .saved = await app.applySettingsPatchAsync(off, expectedRevision: 1) else {
            Issue.record("Off preference did not persist"); return
        }
        let storage = FileHistoryStorage(directory: root)
        var records: [StoredTransition] = []
        for _ in 0..<100 {
            records = storage.load()
            if records.contains(where: { $0.reasonCodes.contains("configApplied") }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(records.contains { $0.reasonCodes.contains("configApplied") && $0.newState == .off })
    }
}
