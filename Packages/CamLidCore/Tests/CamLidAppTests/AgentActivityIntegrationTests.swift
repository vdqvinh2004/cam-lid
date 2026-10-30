import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("Agent activity observer", .serialized)
struct AgentActivityIntegrationTests {
    private func codex(cpu: Double?) -> AgentActivityProcess {
        AgentActivityProcess(provider: "codex", pid: 4242, startTime: 1_700_000_000, cpuSeconds: cpu)
    }

    @Test @MainActor func autoHoldsWhileADirectlyRunAgentWorksAndGivesSleepWhenDoneAfterward() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.mode = .auto; patch.adapterEnrollment = ["codex"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("not saved"); return }
        let t = ContinuousTime.now
        app.receiveActivity([codex(cpu: 10)], sessionAges: ["codex": 2], at: t)          // writing its session file
        await app.startPreviewSession()
        app.changeMode(.auto)
        #expect(app.dashboardData().state == .protected)
        #expect(app.dashboardData().agents.first { $0.provider == "codex" }?.compactDetail.hasSuffix("(estimated)") == true)

        app.receiveActivity([codex(cpu: 10)], sessionAges: ["codex": 999], at: t + 5)     // establishes the CPU baseline
        app.receiveActivity([codex(cpu: 10)], sessionAges: ["codex": 999], at: t + 5 + AgentActivityClassifier.quietSeconds)
        app.receiveProcessSnapshot([], complete: true, observedAt: ContinuousTime.now)   // a fresh, complete process scan
        app.changeMode(.auto)
        #expect(app.dashboardData().state == .completionGrace)                          // idle → "Sleep when done", not "uncertain"
    }

    @Test @MainActor func aVanishedProcessDropsItsTaskAndUnknownNeverHoldsForLong() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let t = ContinuousTime.now
        app.receiveActivity([codex(cpu: nil)], sessionAges: [:], at: t)
        let unknown = try #require(app.sleepRelevantTasksForTesting(provider: "codex").first)
        #expect(unknown.state == .unknown && unknown.evidenceKind == .activity && unknown.confidence == .inferred)
        #expect(unknown.unknownUntilMonotonic == t + AgentActivityClassifier.unknownHoldSeconds)
        app.receiveActivity([], sessionAges: [:], at: t + 5)
        #expect(app.sleepRelevantTasksForTesting(provider: "codex").isEmpty)
    }

    @Test func claudeCodeIsBackWithoutBundledArtwork() {
        let info = AgentProviderCatalog.info(for: "claude")
        #expect(info?.title == "Claude Code" && info?.assetName == nil && info?.processNames == ["claude"])
        #expect(NativeProcessList.agentName(pid: getpid(), processName: "codex") == "codex")
    }

    @Test func badgesSayEstimatedOnlyForActivityEvidence() throws {
        let activity = try AgentTask(id: "a", sessionID: "s", runID: "r", state: .working, evidenceKind: .activity, confidence: .inferred)
        let lifecycle = try AgentTask(id: "b", sessionID: "s", runID: "r2", state: .working, evidenceKind: .lifecycle, confidence: .inferred)
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: [activity]).compactDetail.hasSuffix("(estimated)"))
        #expect(!AgentBadgeState(provider: "codex", enabled: true, tasks: [activity, lifecycle]).estimated)
    }
}
