import Testing
@testable import CamLidCore

@Suite struct AgentActivityClassifierTests {
    private typealias C = AgentActivityClassifier
    private func sample(_ at: Double, cpu: Double? = nil, alive: Bool = true) -> AgentActivitySample {
        AgentActivitySample(at: at, alive: alive, cpuSeconds: cpu)
    }

    @Test func cpuGrowthAboveTheThresholdIsWorking() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0, cpu: 10)) == (.unknown, "warmingUp"))     // no baseline yet
        #expect(C.step(&m, sample(5, cpu: 10.5)) == (.idle, "quiet"))           // one busy sample could be a blip
        #expect(C.step(&m, sample(10, cpu: 11)) == (.working, "cpu"))           // 0.1 core for 10 s: answering
    }

    @Test func calibratedIdleAndWorkingLevelsAreSeparated() {
        var idle = AgentActivityMemory()
        _ = C.step(&idle, sample(0, cpu: 2))
        #expect(C.step(&idle, sample(5, cpu: 2 + 0.015 * 5)) == (.idle, "quiet"))   // highest idle average measured
        var busy = AgentActivityMemory()
        _ = C.step(&busy, sample(0, cpu: 2))
        _ = C.step(&busy, sample(5, cpu: 2 + 0.05 * 5))
        #expect(C.step(&busy, sample(10, cpu: 2 + 0.05 * 10)) == (.working, "cpu"))   // lowest working average measured
    }

    @Test func shortPausesKeepWorkingUntilTheQuietPeriodEnds() {
        var m = AgentActivityMemory()
        _ = C.step(&m, sample(0, cpu: 0))
        _ = C.step(&m, sample(5, cpu: 1))
        #expect(C.step(&m, sample(10, cpu: 2)).state == .working)
        #expect(C.step(&m, sample(15, cpu: 2)) == (.working, "recent"))
        #expect(C.step(&m, sample(10 + C.quietSeconds - 1, cpu: 2)) == (.working, "recent"))
        #expect(C.step(&m, sample(10 + C.quietSeconds, cpu: 2)) == (.idle, "quiet"))
    }

    @Test func exitEndsTheWork() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0, alive: false)) == (.completed, "exited"))
    }

    @Test func unreadableCPUNeverMeansIdle() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0)) == (.unknown, "unreadable"))
        #expect(C.step(&m, sample(5)) == (.unknown, "unreadable"))
    }

    @Test func aChildExitingDuringWorkKeepsWorkingButOtherwiseRestartsTheBaseline() {
        var m = AgentActivityMemory()
        _ = C.step(&m, sample(0, cpu: 50))
        _ = C.step(&m, sample(5, cpu: 51))
        _ = C.step(&m, sample(10, cpu: 52))                                      // working
        #expect(C.step(&m, sample(15, cpu: 20)) == (.working, "recent"))        // subtree total dropped
        var cold = AgentActivityMemory()
        _ = C.step(&cold, sample(0, cpu: 50))
        #expect(C.step(&cold, sample(5, cpu: 1)) == (.idle, "quiet"))              // a drop is not work
        _ = C.step(&cold, sample(10, cpu: 2))
        #expect(C.step(&cold, sample(4, cpu: 3)) == (.unknown, "warmingUp"))    // clock went back
    }

    @Test func evidenceRanksBetweenLifecycleAndProcess() {
        #expect(ProcessDiscovery.rank(kind: .lifecycle) > ProcessDiscovery.rank(kind: .activity))
        #expect(ProcessDiscovery.rank(kind: .activity) > ProcessDiscovery.rank(kind: .process))
        #expect(ProcessDiscovery.confidenceCap(for: .activity) == .inferred)
        #expect(ProcessDiscovery.canArmAuto(kind: .activity))
    }

    @Test func launchCPUIsNotWork() {
        var m = AgentActivityMemory()
        _ = C.step(&m, AgentActivitySample(at: 0, alive: true, cpuSeconds: 0, processAgeSeconds: 2))
        #expect(C.step(&m, AgentActivitySample(at: 5, alive: true, cpuSeconds: 1.5, processAgeSeconds: 7)) == (.idle, "starting"))
        #expect(C.step(&m, AgentActivitySample(at: 25, alive: true, cpuSeconds: 1.6, processAgeSeconds: 27)) == (.idle, "quiet"))
        _ = C.step(&m, AgentActivitySample(at: 30, alive: true, cpuSeconds: 2.2, processAgeSeconds: 32))
        #expect(C.step(&m, AgentActivitySample(at: 35, alive: true, cpuSeconds: 2.8, processAgeSeconds: 37)) == (.working, "cpu"))
    }

    @Test func aChildExitingKeepsAnIdleAgentIdle() {
        var m = AgentActivityMemory()
        _ = C.step(&m, AgentActivitySample(at: 0, alive: true, cpuSeconds: 5, processAgeSeconds: 100))
        #expect(C.step(&m, AgentActivitySample(at: 50, alive: true, cpuSeconds: 5, processAgeSeconds: 150)) == (.idle, "quiet"))
        #expect(C.step(&m, AgentActivitySample(at: 55, alive: true, cpuSeconds: 3, processAgeSeconds: 155)) == (.idle, "quiet"))
        _ = C.step(&m, AgentActivitySample(at: 60, alive: true, cpuSeconds: 4, processAgeSeconds: 160))
        #expect(C.step(&m, AgentActivitySample(at: 65, alive: true, cpuSeconds: 5, processAgeSeconds: 165)) == (.working, "cpu"))
    }

    /// Owner saw "1 working" on an idle Claude Code (2026-11-01): a single busy sample, or the first sample after the
    /// Mac slept, is not work.
    @Test func aBlipOrAWakeIsNotWork() {
        var m = AgentActivityMemory()
        _ = C.step(&m, sample(0, cpu: 1))
        #expect(C.step(&m, sample(5, cpu: 1.5)) == (.idle, "quiet"))            // one 0.1-core sample
        #expect(C.step(&m, sample(10, cpu: 1.52)) == (.idle, "quiet"))
        #expect(C.step(&m, sample(310, cpu: 30)) == (.idle, "quiet"))           // 5 min gap: the Mac slept
        #expect(C.step(&m, sample(315, cpu: 30.05)) == (.idle, "quiet"))
    }
}
