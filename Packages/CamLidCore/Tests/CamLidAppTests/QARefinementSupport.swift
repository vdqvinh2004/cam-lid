import Foundation
import CamLidCore
@testable import CamLidApp

@MainActor
struct QARefinementSupport {
    let root = URL(fileURLWithPath: "/tmp/camlid-refinement-" + UUID().uuidString)
    var suite: String { "CamLidTest." + root.lastPathComponent }
    func makeCoordinator(failingWrites: Bool = false, outcomeNotifications: OutcomeNotifications? = nil, permissions: AppPermissions? = nil,
        healthReader: (() -> HealthSnapshot)? = { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) }) -> AppCoordinator {
        let failure: @Sendable (Data, URL) throws -> Void = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let writer: (@Sendable (Data, URL) throws -> Void)? = failingWrites ? failure : nil
        return AppCoordinator(historyDirectory: root.appendingPathComponent("history"),
            controlDirectory: root.appendingPathComponent("control"),
            preferences: UserDefaults(suiteName: suite)!,
            settingsWriter: writer, outcomeNotifications: outcomeNotifications, permissions: permissions, healthReader: healthReader)
    }
    func cleanup() { UserDefaults().removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}


/// All five M4b stories have isolated render/state fixtures. These never enter
/// AppCoordinator sensor/power inputs or a production preferences domain.
@MainActor
extension QARefinementSupport {
    func dashboardFixture(state: EffectiveState = .unavailable) -> DashboardData {
        DashboardData(mode: .auto, state: state, reasonText: "Isolated QA fixture",
            tasks: (0..<20).map { DashboardTaskRow(id: "fixture-\($0)", provider: "Codex long provider label", stateText: "unknown", confidenceText: "unknown") },
            taskSummaryText: "20 fixture tasks", temperatureText: "Unavailable · no qualified sensor",
            isStale: true, banner: .unsupported, bannerMessage: "Fixture · no power actuation", stopEnabled: false)
    }
    func preferencesFixture() throws -> SettingsEditor {
        let editor = SettingsEditor(configuration: try Configuration(completionDelayMinutes: 7), revision: 1)
        editor.configureAsyncAutosave { _, _ in .failed("Fixture storage failure") }
        return editor
    }
    func sensorFixtures() -> [SensorReadings] {
        [SensorReadings(thermalPressure: .nominal, measuredAtMonotonic: 20,
            lidObservation: LidObservation(state: .closed, sampledAtMonotonic: 20)),
         SensorReadings(thermalPressure: .critical, measuredAtMonotonic: 20,
            lidObservation: LidObservation(state: .open, sampledAtMonotonic: 10)),
         SensorReadings(measuredAtMonotonic: 20)]
    }
    func agentFixtures() throws -> [AgentBadgeState] {
        try ["orca", "codex", "opencode", "claude"].enumerated().map { index, provider in
            let state: TaskState = [.working, .waiting, .idle, .unknown][index]
            let task = try AgentTask(id: "fixture-" + provider, sessionID: "fixture", runID: provider,
                state: state, evidenceKind: .lifecycle, confidence: state == .unknown ? .unknown : .exact)
            return AgentBadgeState(provider: provider, enabled: true, tasks: [task], evidenceAgeSeconds: 0)
        }
    }
    func protectionFixture() -> ProtectionReadiness {
        ProtectionReadiness(facts: ProtectionReadinessFacts(buildKind: .preview, supportRowID: nil,
            supportRowQualified: false, helperTrusted: false, helperAvailable: false, recoveryRequired: false,
            recoveryJournalReady: false, ownershipEvidence: .unknown, matchingGlobalOverrideObserved: false,
            backendVerified: false, leaseVerified: false, safetyQualifying: false, requestedClosedLidIntent: true))
    }
}
