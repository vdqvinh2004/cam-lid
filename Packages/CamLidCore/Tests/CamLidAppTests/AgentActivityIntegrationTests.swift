import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("Agent activity observer", .serialized)
struct AgentActivityIntegrationTests {
    private func codex(cpu: Double?) -> AgentActivityProcess {
        AgentActivityProcess(provider: "codex", pid: 4242, startTime: 1_700_000_000, cpuSeconds: cpu)
    }

    /// An agent inside Orca is Orca's to report: its CPU never holds the Mac through the activity observer.
    @Test @MainActor func anOrcaHostedAgentIsNotSampled() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var hosted = codex(cpu: 10); hosted.orcaHosted = true
        app.receiveActivity([hosted], at: ContinuousTime.now)
        #expect(app.sleepRelevantTasksForTesting(provider: "codex").isEmpty)
    }

    @Test @MainActor func autoHoldsWhileADirectlyRunAgentWorksAndGivesSleepWhenDoneAfterward() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.mode = .auto; patch.adapterEnrollment = ["codex"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("not saved"); return }
        let t = ContinuousTime.now
        app.receiveActivity([codex(cpu: 10)], at: t - 5)
        app.receiveActivity([codex(cpu: 10.5)], at: t)                                   // 0.1 core: answering
        await app.startPreviewSession()
        app.changeMode(.auto)
        #expect(app.dashboardData().state == .protected)
        #expect(app.dashboardData().agents.first { $0.provider == "codex" }?.compactDetail.hasSuffix("(estimated)") == true)

        app.receiveActivity([codex(cpu: 10.5)], at: t + 5)
        app.receiveActivity([codex(cpu: 10.5)], at: t + AgentActivityClassifier.quietSeconds)
        app.receiveProcessSnapshot([], complete: true, observedAt: ContinuousTime.now)   // a fresh, complete process scan
        app.changeMode(.auto)
        #expect(app.dashboardData().state == .completionGrace)                          // idle → "Sleep when done", not "uncertain"
    }

    @Test @MainActor func aVanishedProcessDropsItsTaskAndUnknownNeverHoldsForLong() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let t = ContinuousTime.now
        app.receiveActivity([codex(cpu: nil)], at: t)
        let unknown = try #require(app.sleepRelevantTasksForTesting(provider: "codex").first)
        #expect(unknown.state == .unknown && unknown.evidenceKind == .activity && unknown.confidence == .inferred)
        #expect(unknown.unknownUntilMonotonic == t + AgentActivityClassifier.unknownHoldSeconds)
        app.receiveActivity([], at: t + 5)
        #expect(app.sleepRelevantTasksForTesting(provider: "codex").isEmpty)
    }

    @Test func claudeCodeIsBackWithItsOfficialMark() {
        let info = AgentProviderCatalog.info(for: "claude")
        #expect(info?.title == "Claude Code" && info?.assetName == "agent-claude" && info?.processNames == ["claude"])
        #expect(NativeProcessList.agentName(pid: getpid(), processName: "codex") == "codex")
    }

    @Test func badgesSayEstimatedOnlyForActivityEvidence() throws {
        let activity = try AgentTask(id: "a", sessionID: "s", runID: "r", state: .working, evidenceKind: .activity, confidence: .inferred)
        let lifecycle = try AgentTask(id: "b", sessionID: "s", runID: "r2", state: .working, evidenceKind: .lifecycle, confidence: .inferred)
        #expect(AgentBadgeState(provider: "codex", enabled: true, tasks: [activity]).compactDetail.hasSuffix("(estimated)"))
        #expect(!AgentBadgeState(provider: "codex", enabled: true, tasks: [activity, lifecycle]).estimated)
    }

    /// Terminals start shells through a root-owned `login`; the ancestor walk must still read it (Orca's host is above it).
    @Test func theKernelTableReadsAnyProcessesParent() {
        #expect(NativeProcessList.kernelEntry(getpid())?.parent == getppid())
        #expect(NativeProcessList.kernelEntry(1)?.name == "launchd")
        #expect(NativeProcessList.kernelEntry(1)?.uid == 0)
    }

    /// Trial 8: root-owned processes made every scan "incomplete", so Auto never trusted a completion.
    @Test func otherUsersProcessesDoNotMakeTheScanIncomplete() {
        #expect(NativeProcessList().agentSnapshot().complete)
        // Some of the user's own processes refuse inspection; they leave a scan incomplete only if they could match.
        #expect(NativeProcessList().lifetimeSnapshot(ruleNames: ["no-such-tool"])?.complete == true)
        let path = try! LifetimeRule(selectorKind: .exactExecutablePath, selectorValue: "/opt/tools/A-Very-Long-Worker-Name", label: "W")
        let bundle = try! LifetimeRule(selectorKind: .applicationBundleID, selectorValue: "com.example.app", label: "App")
        #expect(NativeProcessList.kernelNames(of: [path]) == ["a-very-long-work"])
        #expect(NativeProcessList.kernelNames(of: [path, bundle]) == nil)
    }
}
