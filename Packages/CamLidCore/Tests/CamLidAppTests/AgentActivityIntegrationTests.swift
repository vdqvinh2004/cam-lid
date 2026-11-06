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

    /// The stop menu offers up to 50 percent; with a lower start level the refusal must say what to change.
    @Test @MainActor func aStopLevelAtOrAboveTheStartLevelIsRefusedWithAnExplanation() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var start = ConfigPatch(); start.batteryEntryPercent = 30
        guard case .saved = app.applySettingsPatch(start, expectedRevision: 1) else { Issue.record("not saved"); return }
        var stop = ConfigPatch(); stop.batteryFloorPercent = 40
        guard case .failed(let message) = app.applySettingsPatch(stop, expectedRevision: 2) else {
            Issue.record("a stop level above the start level was accepted"); return
        }
        #expect(message.contains("Start on battery at or above"))
        #expect(app.settingsRefusal(for: ConfigPatch()) == "Invalid setting. Last applied value retained.")
    }

    @Test @MainActor func autoHoldsWhileADirectlyRunAgentWorksAndGivesSleepWhenDoneAfterward() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.mode = .auto; patch.adapterEnrollment = ["codex"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("not saved"); return }
        let t = ContinuousTime.now
        app.receiveActivity([codex(cpu: 9.5)], at: t - 10)
        app.receiveActivity([codex(cpu: 10)], at: t - 5)
        app.receiveActivity([codex(cpu: 10.5)], at: t)                                   // 0.1 core for 10 s: answering
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
        #expect(unknown.unknownUntilMonotonic == nil)   // never seen working: an unreadable first sample holds nothing
        app.receiveActivity([], at: t + 5)
        #expect(app.sleepRelevantTasksForTesting(provider: "codex").isEmpty)
    }

    @Test func repeatedUnknownReadingsDoNotExtendTheHoldPastTheLastWork() {
        var memory = AgentActivityMemory()
        let t = 1_000.0
        func sample(_ at: Double, _ cpu: Double?) -> TaskState {
            AgentActivityClassifier.step(&memory, AgentActivitySample(at: at, alive: true, cpuSeconds: cpu, processAgeSeconds: 600)).state
        }
        _ = sample(t, 0)
        _ = sample(t + 5, 1)
        #expect(sample(t + 10, 2) == .working)
        let deadline = t + 10 + AgentActivityClassifier.unknownHoldSeconds
        #expect(AgentActivityClassifier.unknownHoldDeadline(memory) == deadline)
        for offset in [15.0, 20, 30] { #expect(sample(t + offset, nil) == .unknown) }
        #expect(AgentActivityClassifier.unknownHoldDeadline(memory) == deadline)   // not pushed out by unknown readings
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

    /// Activity shows when a terminal agent starts and stops working, as it does for Orca.
    @Test @MainActor func activityStateChangesReachHistory() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let t = ContinuousTime.now
        for (i, cpu) in [1.0, 1.5, 2.0, 2.0].enumerated() { app.receiveActivity([codex(cpu: cpu)], at: t + Double(i) * 5) }
        app.receiveActivity([codex(cpu: 2.0)], at: t + 15 + AgentActivityClassifier.quietSeconds)
        #expect(await app.flushHistory(timeout: 2))
        let text = try FileManager.default.contentsOfDirectory(at: fixture.root.appendingPathComponent("history"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(text.components(separatedBy: "codex:working").count - 1 == 1)
        #expect(text.components(separatedBy: "codex:idle").count - 1 == 1)
    }

    /// Script CLIs run under an interpreter; the kernel calls them `node` or `python` (Pi and Freebuff were invisible).
    @Test func agentsRunByAnInterpreterAreNamedFromTheirArguments() {
        #expect(NativeProcessList.isInterpreter("node") && NativeProcessList.isInterpreter("python3.12"))
        #expect(!NativeProcessList.isInterpreter("codex"))
        #expect(NativeProcessList.agent(fromArguments: ["pi"]) == "pi")                                // process.title
        #expect(NativeProcessList.agent(fromArguments: ["node", "/Users/x/.nvm/bin/freebuff"]) == "freebuff")
        #expect(NativeProcessList.agent(fromArguments: ["/usr/bin/python3", "/opt/bin/aider"]) == "aider")
        #expect(NativeProcessList.agent(fromArguments: ["node", "server.js", "pi"]) == nil)          // a script argument
        #expect(NativeProcessList.agentName(pid: getpid(), processName: "node") == "node")
    }
}
