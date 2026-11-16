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

    /// Anything running under Orca is reported as Orca's, never under the provider of the agent it runs.
    @Test func anAgentRunningUnderOrcaIsReportedAsOrca() {
        var process = AgentActivityProcess(provider: "claude", pid: 6, startTime: 1_700_000_000, cpuSeconds: 1)
        #expect(process.reportedProvider == "claude")
        process.underOrca = true
        #expect(process.reportedProvider == "orca")
    }

    @Test @MainActor func anAgentRunningUnderOrcaIsTasksOfOrcaOnly() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var inOrca = AgentActivityProcess(provider: "pi", pid: 8, startTime: 1_700_000_000, cpuSeconds: 1)
        inOrca.underOrca = true
        app.receiveActivity([inOrca], at: ContinuousTime.now)
        #expect(app.sleepRelevantTasksForTesting(provider: "orca").count == 1)
        #expect(app.sleepRelevantTasksForTesting(provider: "pi").isEmpty)
    }

    /// Orca's own process and every agent running under it count under Orca; an agent provider counts only what runs
    /// outside Orca.
    @Test func processesRunningUnderOrcaAreCountedUnderOrcaOnly() {
        let providers = ["orca", "claude"]
        #expect(AppCoordinator.processCount(for: "orca", candidateProviders: providers, orcaRunAgents: 3) == 4)
        #expect(AppCoordinator.processCount(for: "claude", candidateProviders: providers, orcaRunAgents: 3) == 1)
        #expect(AppCoordinator.processCount(for: "pi", candidateProviders: providers, orcaRunAgents: 3) == 0)
    }

    /// Orca's fresh report decides for each provider it names an agent of. A provider it names none of is sampled, so an
    /// agent Orca does not report (freebuff, or an unhooked session) is not invisible.
    @Test func orcaReportDecidesOnlyForTheProvidersItNames() {
        var codexOne = codex(cpu: 1); codexOne.underOrca = true
        var codexTwo = codex(cpu: 2); codexTwo.underOrca = true
        var freebuff = AgentActivityProcess(provider: "freebuff", pid: 5, startTime: 1_700_000_000, cpuSeconds: 4)
        freebuff.underOrca = true
        let processes = [codexOne, codexTwo, freebuff]
        #expect(processes.applyingOrcaReports(reportedProviders: ["codex"]).map(\.orcaHosted) == [true, true, false])
        #expect(processes.applyingOrcaReports(reportedProviders: ["codex", "freebuff"]).map(\.orcaHosted) == [true, true, true])
        #expect(processes.applyingOrcaReports(reportedProviders: []).map(\.orcaHosted) == [false, false, false])
        #expect(processes.applyingOrcaReports(reportedProviders: nil).map(\.orcaHosted) == [false, false, false])
    }

    /// A process that does not run under Orca is never left to Orca, however many agents Orca reports.
    @Test func aProcessOutsideOrcaIsNeverLeftToOrca() {
        let outside = AgentActivityProcess(provider: "claude", pid: 9, startTime: 1_700_000_000, cpuSeconds: 1)
        #expect([outside].applyingOrcaReports(reportedProviders: ["claude"]).map(\.orcaHosted) == [false])
    }

    /// An agent Orca reports leaves no CPU work under Orca, so its CPU cannot count again on top of Orca's state; an
    /// agent of a provider Orca does not name still counts there.
    @Test @MainActor func aProviderOrcaReportsAddsNoCPUWorkUnderOrca() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var claude = AgentActivityProcess(provider: "claude", pid: 11, startTime: 1_700_000_000, cpuSeconds: 1)
        claude.underOrca = true
        var freebuff = AgentActivityProcess(provider: "freebuff", pid: 12, startTime: 1_700_000_000, cpuSeconds: 1)
        freebuff.underOrca = true
        app.receiveActivity([claude, freebuff].applyingOrcaReports(reportedProviders: ["claude"]), at: ContinuousTime.now)
        #expect(app.sleepRelevantTasksForTesting(provider: "orca").count == 1)
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

    @Test func orcaUnknownDoesNotBlockCompletionButAnUnknownCodexDoes() {
        // Orca's app process runs whenever Orca is open and reports "Unknown" with no task: its completion is the
        // metadata rule's. A Codex process with no task reported is still uncertain.
        let orca = AgentBadgeState(provider: "orca", enabled: true, tasks: [], processCount: 1)
        let idleCodex = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 0)
        let unknownCodex = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1)
        #expect(orca.observedState == "Unknown")
        #expect(!AppCoordinator.badgesLeaveCompletionUnproven([orca], activityClassified: { _ in true }))
        #expect(!AppCoordinator.badgesLeaveCompletionUnproven([idleCodex], activityClassified: { _ in true }))
        #expect(AppCoordinator.badgesLeaveCompletionUnproven([unknownCodex], activityClassified: { _ in true }))
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

    /// A process inside Orca is recognised by its ancestry, past the root-owned `login` (Orca's host sits above it). The
    /// same agent started from Ghostty has no Orca ancestor.
    @Test func ancestryFindsOrcaPastRootOwnedLogin() {
        let tree: [Int32: (parent: Int32, name: String)] = [
            99741: (99740, "freebuff"), 99740: (99528, "node"), 99528: (99527, "zsh"), 99527: (40167, "login"),
            40167: (1, "orca terminal h"),
            79041: (78452, "claude"), 78452: (78451, "zsh"), 78451: (691, "login"), 691: (1, "ghostty"),
        ]
        let inOrca = NativeProcessList.ancestorNames(of: 99741) { tree[$0] }
        let outside = NativeProcessList.ancestorNames(of: 79041) { tree[$0] }
        #expect(inOrca == ["node", "zsh", "login", "orca terminal h"])
        #expect(inOrca.contains { $0.hasPrefix("orca") })
        #expect(!outside.contains { $0.hasPrefix("orca") })
        #expect(!NativeProcessList.runsUnderOrca(1))
    }

    /// freebuff run outside Orca is freebuff's own work, not Orca's.
    @Test @MainActor func aFreebuffOutsideOrcaIsTasksOfFreebuffOnly() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let freebuff = AgentActivityProcess(provider: "freebuff", pid: 13, startTime: 1_700_000_000, cpuSeconds: 1)
        app.receiveActivity([freebuff], at: ContinuousTime.now)
        #expect(app.sleepRelevantTasksForTesting(provider: "freebuff").count == 1)
        #expect(app.sleepRelevantTasksForTesting(provider: "orca").isEmpty)
    }
}
