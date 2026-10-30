import Testing
import AppKit
import SwiftUI
import CamLidCore
@testable import CamLidApp
struct AgentBadgeTests {
    @Test @MainActor func agentBadgeKeepsMarkInsidePaddedSlot() {
        let badge = AgentBadge(provider: "orca", title: "Orca")
        let host = NSHostingController(rootView: badge)
        host.sizingOptions = []
        let size = host.sizeThatFits(in: NSSize(width: 400, height: 100))
        #expect(AgentBadgeMetrics.markSize < AgentBadgeMetrics.markSlotSize)
        #expect(size.height >= AgentBadgeMetrics.markSlotSize + AgentBadgeMetrics.verticalPadding * 2)
    }

    @Test func orcaExplanationSeparatesReceiptAgeFromStateFreshness() throws {
        let task = try AgentTask(id: "orca/pane", sessionID: "outside", runID: "pane",
            state: .working, evidenceKind: .lifecycle, confidence: .inferred)
        let active = AgentBadgeState(provider: "orca", enabled: true, tasks: [task], evidenceAgeSeconds: 3)
        #expect(active.workingCount == 1 && active.observedState == "Active")
        #expect(active.observationExplanation.contains("Reported confidence: inferred"))
        #expect(active.observationExplanation.contains("source receipt") && active.observationExplanation.contains("not task-state age"))
        #expect(active.observationExplanation.contains("freshness is unverified") && active.observationExplanation.contains("does not prove all jobs"))
        for rows in [[], [try row("idle", .idle)]] {
            let inactive = AgentBadgeState(provider: "orca", enabled: true, tasks: rows, evidenceAgeSeconds: 0, cliDetected: true)
            #expect(inactive.installationText == "CLI detected" && inactive.workingCount == 0)
            #expect(inactive.observationExplanation.contains("freshness is unverified") && inactive.observationExplanation.contains("does not prove all jobs"))
        }
    }
    @Test func receiptExplanationRejectsInvalidAgesAndBoundsOldAgeText() {
        for age in [Double.nan, .infinity, -.infinity, -1] {
            let state = AgentBadgeState(provider: "orca", enabled: true, tasks: [], evidenceAgeSeconds: age)
            #expect(state.observationExplanation.contains("receipt age unavailable"))
        }
        let old = AgentBadgeState(provider: "orca", enabled: true, tasks: [], evidenceAgeSeconds: .greatestFiniteMagnitude)
        #expect(old.observationExplanation.contains("at least 1 hr ago"))
    }
    @Test func processExplanationNeverPromotesInstallationOrPresenceToWork() {
        let state = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1, cliDetected: true)
        #expect(state.observedState == "Unknown" && state.workingCount == 0 && state.waitingCount == 0)
        #expect(state.observationExplanation.contains("confidence: unknown") && state.observationExplanation.contains("Process presence alone does not prove activity or completion"))
        #expect(AgentBadgeState.workingSummary([state]).contains("No selected agents reporting work"))
    }
    func row(_ id: String, _ state: TaskState) throws -> AgentTask {
        try AgentTask(id: "orca/" + id, sessionID: id, runID: id, state: state, evidenceKind: .lifecycle, confidence: .exact)
    }
    @Test func unknownCoverageIsNotPresentedAsAbsenceInCompactBadge() {
        let badge = AgentBadgeState(provider: "orca", enabled: true, tasks: [], observationKnown: false)
        #expect(badge.observedState == "Unknown" && badge.compactDetail == "No task reported")
    }
    @Test func enrollmentDoesNotInventActivity() {
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: []).observedState == "Not detected")
    }
    @Test func parallelAndUnknownAggregation() throws {
        let rows = try [row("a", .idle), row("b", .working), row("c", .unknown)]
        let active = AgentBadgeState(provider: "orca", enabled: true, tasks: rows)
        #expect(active.observedState == "Active" && active.workingCount == 1 && active.unknownCount == 1)
        #expect(AgentBadgeState(provider: "orca", enabled: true, tasks: try [row("a", .idle), row("b", .unknown)]).observedState == "Unknown")
        #expect(AgentBadgeState(provider: "orca", enabled: false, tasks: rows).observedState == "Active")
    }
    @Test func staleIdleAndWaitingRemainDistinct() throws {
        #expect(AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("a", .idle)], evidenceAgeSeconds: 16).observedState == "Unknown")
        #expect(AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("a", .waiting)], evidenceAgeSeconds: 16).observedState == "Waiting")
        let hashed = try AgentTask(id: "evt-123", sessionID: "s", runID: "r", state: .working, evidenceKind: .lifecycle, confidence: .exact)
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: [hashed]).observedState == "Active")
    }
    @Test func dashboardShowsOnlyWorkingEnabledAgents() throws {        let working = AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("a", .working)])
        let idle = AgentBadgeState(provider: "codex", enabled: true, tasks: [try row("b", .idle)])
        let disabled = AgentBadgeState(provider: "cursor", enabled: false, tasks: [try row("c", .working)])
        let unknown = AgentBadgeState(provider: "opencode", enabled: true, tasks: [try row("d", .unknown)])
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "",
            agents: [working, idle, disabled, unknown])
        #expect(data.workingAgents.map(\.provider) == ["orca"])
        #expect(DashboardData(mode: .off, state: .off, reasonText: "").workingAgents.isEmpty)
    }
    @Test func settingsAvailabilityReflectsDetectionSupport() {
        let soon = AgentBadgeState(provider: "vscode-copilot", enabled: false, tasks: [])
        #expect(!soon.supportsDetection && soon.settingsUnavailableReason == "Support soon")
        let absent = AgentBadgeState(provider: "cursor", enabled: false, tasks: [])
        #expect(absent.supportsDetection && absent.settingsUnavailableReason == "Not detected")
        let cli = AgentBadgeState(provider: "freebuff", enabled: false, tasks: [], cliDetected: true)
        #expect(cli.settingsUnavailableReason == nil && cli.isDetected)
        let app = AgentBadgeState(provider: "antigravity", enabled: false, tasks: [], appDetected: true)
        #expect(app.settingsUnavailableReason == nil && app.installationText == "App detected")
    }

    @Test func providerMarksMapToBundledAssets() {
        for info in AgentProviderCatalog.providers {
            let state = AgentBadgeState(provider: info.id, enabled: true, tasks: [])
            #expect(state.markAssetName == info.assetName)
        }
        #expect(AgentBadgeState(provider: "opencode", enabled: true, tasks: []).markAssetName == nil)
        #expect(AgentBadgeState(provider: "opencode", enabled: true, tasks: []).usesVectorMark)
        #expect(AgentBadgeState(provider: "mystery", enabled: true, tasks: []).markAssetName == nil)
    }
    @Test @MainActor func bundledMarksLoadAtRuntime() {
        // Exercises the real production path (Bundle.module inside CamLidApp).
        for info in AgentProviderCatalog.providers where info.assetName != nil {
            guard let image = AgentMarkView.image(for: info.id) else {
                Issue.record("missing bundled mark: \(info.id)")
                continue
            }
            #expect(image.size.width > 0 && image.size.height > 0)
        }
        #expect(AgentMarkView.image(for: "opencode") == nil)
        #expect(AgentMarkView.image(for: "mystery") == nil)
    }
    @Test func waitingSummaryAndDetailStayDistinctFromWork() throws {
        let waiting = AgentBadgeState(provider: "opencode", enabled: true, tasks: [try row("a", .waiting)])
        #expect(waiting.waitingCount == 1 && waiting.observedState == "Waiting")
        #expect(waiting.compactDetail == "Waiting for user · 1 task")
        #expect(waiting.detail.contains("Waiting for user"))
        #expect(waiting.observationExplanation.contains("never keep the machine awake"))
        #expect(AgentBadgeState.waitingSummary([waiting]) == "1 selected agent waiting for user")
        #expect(AgentBadgeState.waitingSummary([]) == "No selected agents waiting for user")
        let mixed = AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("w", .working), try row("q", .waiting)])
        #expect(AgentBadgeState.waitingSummary([waiting, mixed]) == "1 selected agent waiting for user")
        #expect(AgentBadgeState.workingSummary([waiting, mixed]) == "1 selected agent reporting work")
    }
    @Test func dashboardListsWaitingSeparatelyFromWorking() throws {
        let working = AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("a", .working)])
        let waiting = AgentBadgeState(provider: "opencode", enabled: true, tasks: [try row("b", .waiting)])
        let both = AgentBadgeState(provider: "codex", enabled: true, tasks: [try row("c", .working), try row("d", .waiting)])
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "",
            agents: [working, waiting, both])
        #expect(data.workingAgents.map(\.provider) == ["codex", "orca"])
        #expect(data.waitingAgents.map(\.provider) == ["opencode"])
        #expect(data.listedAgents.map(\.provider) == ["codex", "opencode", "orca"])
    }
    @Test func agentBadgeDisplayOrderIsAlphabeticalAndDetectedFirst() {
        let windsurf = AgentBadgeState(provider: "windsurf", enabled: true, tasks: [])
        let codex = AgentBadgeState(provider: "codex", enabled: true, tasks: [], cliDetected: true)
        let aider = AgentBadgeState(provider: "aider", enabled: true, tasks: [])
        let antigravity = AgentBadgeState(provider: "antigravity", enabled: true, tasks: [], appDetected: true)
        let agents = [windsurf, codex, aider, antigravity]

        #expect(agents.sortedForAgentDisplay().map(\.title)
            == ["Aider", "Antigravity", "Codex", "Windsurf / Devin"])
        #expect(agents.sortedForAgentDisplay(detectedFirst: true).map(\.provider)
            == ["antigravity", "codex", "aider", "windsurf"])
    }
    @Test func mixedWorkingAndWaitingShowsBothCountsWaitingFirst() throws {
        let mixed = AgentBadgeState(provider: "orca", enabled: true, tasks: [try row("w", .working), try row("q", .waiting)])
        #expect(mixed.workingCount == 1 && mixed.waitingCount == 1)
        #expect(mixed.compactDetail.contains("Active") && mixed.compactDetail.contains("1 waiting"))
        #expect(mixed.detail.contains("1 waiting"))
        #expect(AgentBadgeState.workingSummary([mixed]) == "1 selected agent reporting work")
        #expect(AgentBadgeState.waitingSummary([mixed]) == "No selected agents waiting for user")
    }
}