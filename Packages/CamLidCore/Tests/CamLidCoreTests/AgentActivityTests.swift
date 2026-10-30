import Testing
@testable import CamLidCore

@Suite struct AgentActivityClassifierTests {
    private typealias C = AgentActivityClassifier
    private func sample(_ at: Double, cpu: Double? = nil, file: Double? = nil, alive: Bool = true) -> AgentActivitySample {
        AgentActivitySample(at: at, alive: alive, cpuSeconds: cpu, sessionFileAgeSeconds: file)
    }

    @Test func cpuGrowthAboveTheThresholdIsWorking() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0, cpu: 10)) == (.unknown, "warmingUp"))     // no baseline yet
        #expect(C.step(&m, sample(5, cpu: 10.5)) == (.working, "cpu"))          // 0.1 core
    }

    @Test func aRecentSessionWriteIsWorkingEvenWithoutCPU() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0, file: 3)) == (.working, "sessionFile"))
    }

    @Test func shortPausesKeepWorkingUntilTheQuietPeriodEnds() {
        var m = AgentActivityMemory()
        _ = C.step(&m, sample(0, cpu: 0))
        #expect(C.step(&m, sample(5, cpu: 1)).state == .working)
        #expect(C.step(&m, sample(10, cpu: 1, file: 999)) == (.working, "recent"))
        #expect(C.step(&m, sample(5 + C.quietSeconds - 1, cpu: 1, file: 999)) == (.working, "recent"))
        #expect(C.step(&m, sample(5 + C.quietSeconds, cpu: 1, file: 999)) == (.idle, "quiet"))
    }

    @Test func aProcessWaitingForInputIsIdle() {
        var m = AgentActivityMemory()
        _ = C.step(&m, sample(0, cpu: 2, file: 3_600))
        #expect(C.step(&m, sample(5, cpu: 2.01, file: 3_605)) == (.idle, "quiet"))   // 0.002 core
    }

    @Test func exitEndsTheWork() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0, alive: false)) == (.completed, "exited"))
    }

    @Test func unreadableSignalsNeverMeanIdle() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0)) == (.unknown, "unreadable"))
        #expect(C.step(&m, sample(5)) == (.unknown, "unreadable"))
    }

    @Test func onlyTheFileSignalCanStillShowQuiet() {
        var m = AgentActivityMemory()
        #expect(C.step(&m, sample(0, file: 600)) == (.idle, "quiet"))
    }

    @Test func aCPUDropOrAClockJumpRestartsTheBaseline() {
        var m = AgentActivityMemory()
        _ = C.step(&m, sample(0, cpu: 50))
        #expect(C.step(&m, sample(5, cpu: 1)) == (.unknown, "warmingUp"))       // pid reuse
        _ = C.step(&m, sample(10, cpu: 2))
        #expect(C.step(&m, sample(4, cpu: 3)) == (.unknown, "warmingUp"))       // clock went back
    }

    @Test func evidenceRanksBetweenLifecycleAndProcess() {
        #expect(ProcessDiscovery.rank(kind: .lifecycle) > ProcessDiscovery.rank(kind: .activity))
        #expect(ProcessDiscovery.rank(kind: .activity) > ProcessDiscovery.rank(kind: .process))
        #expect(ProcessDiscovery.confidenceCap(for: .activity) == .inferred)
        #expect(ProcessDiscovery.canArmAuto(kind: .activity))
    }
}
