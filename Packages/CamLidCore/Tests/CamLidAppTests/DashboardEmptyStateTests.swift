import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Dashboard empty-state settings route", .serialized)
struct DashboardEmptyStateTests {
    private func row(_ provider: String, _ id: String, _ state: TaskState) throws -> AgentTask {
        try AgentTask(id: provider + "/" + id, sessionID: id, runID: id, state: state,
            evidenceKind: .lifecycle, confidence: .exact)
    }

    @Test func runningRowsShowOnlyWorkingEnabledAgents() throws {
        let working = AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("orca", "a", .working)])
        let idle = AgentBadgeState(provider: "codex", enabled: true, tasks: [try row("codex", "b", .idle)])
        let unknown = AgentBadgeState(provider: "opencode", enabled: true, tasks: [try row("opencode", "d", .unknown)])
        let disabled = AgentBadgeState(provider: "claude", enabled: false, tasks: [try row("claude", "c", .working)])
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "",
            agents: [working, idle, disabled, unknown])
        #expect(data.workingAgents.map(\.provider) == ["orca"])
        #expect(data.hasEnabledAgents)
        #expect(!DashboardData(mode: .auto, state: .ready, reasonText: "",
            agents: [AgentBadgeState(provider: "codex", enabled: false, tasks: [])]).hasEnabledAgents)
        #expect(!DashboardData(mode: .off, state: .off, reasonText: "").hasEnabledAgents)
    }
    @Test func settingsEventRoundTrips() throws {
        let data = try JSONEncoder().encode(UtilityUIEvent.settings(.agents))
        guard case .settings(.agents) = try JSONDecoder().decode(UtilityUIEvent.self, from: data) else {
            Issue.record("settings event did not round-trip"); return
        }
    }

    @Test @MainActor func settingsEventSelectsAgentsPaneWithoutDisturbingSession() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        app.receiveUtilityEvent(.settings(.agents))
        let stored = fixture.preferences.string(forKey: "CamLidSettingsSection")
        #expect(stored == SettingsSection.agents.rawValue)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        #expect(reply.exitCode == 0)
    }

}
