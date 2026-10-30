import Foundation
import Darwin
import Testing
@_spi(TestInputs) import LidNativeAdapter
@_spi(TestInputs) import LidRecoveryBroker

@Suite("Safety worker and disabled launcher", .serialized)
struct NativeSafetySamplerTests {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var nanos: UInt64 = 1_000_000_000
        var pressure: NativeThermalState = .nominal
        var reads = 0
        private var faultEnabled = false
        var clockFaultEnabled: Bool { lock.withLock { faultEnabled } }
        func enableClockFault() { lock.withLock { faultEnabled = true } }
        var clock: BrokerClockSnapshot {
            lock.withLock { BrokerClockSnapshot(bootID: "00000000-0000-0000-0000-000000000001", nowNanos: nanos) }
        }
        func advance(_ value: UInt64) { lock.withLock { nanos += value } }
        func hot() { lock.withLock { pressure = .critical } }
        var thermal: NativeThermalState { lock.withLock { pressure } }
        var readCount: Int { lock.withLock { reads } }
        func readStarted() { lock.withLock { reads += 1 } }
    }
    private final class Gate: @unchecked Sendable {
        let condition = NSCondition()
        var opened = false
        func block() {
            condition.lock(); defer { condition.unlock() }
            let deadline = Date().addingTimeInterval(3)
            while !opened { if !condition.wait(until: deadline) { return } }
        }
        func open() { condition.lock(); opened = true; condition.broadcast(); condition.unlock() }
    }
    private func sampler(_ state: State, batteryRead: @escaping @Sendable () -> Void = {}) -> NativeSafetySampler {
        let calls = NativeSafetySystemCalls(batteries: {
            state.readStarted(); batteryRead()
            return [["Type": "InternalBattery", "Is Present": true, "Current Capacity": 75,
                     "Max Capacity": 100, "Power Source State": "AC Power"]]
        }, lidProperty: { kCFBooleanFalse }, displays: { [1] }, displayFlags: { _ in
            NativeDisplayFlags(builtin: 1, online: 1, asleep: 0)
        }, thermal: { state.thermal })
        return NativeSafetySampler(systemCalls: calls, clock: { state.clock })
    }
    private func wait(_ predicate: () -> Bool) throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if predicate() { return }
            Thread.sleep(forTimeInterval: 0.005)
        }
        throw BrokerFailure.timeout
    }

    @Test func pendingHungSourceStaysUnknownWithoutQueuePileupOrThermalBlindness() throws {
        let state = State(); let gate = Gate()
        defer { gate.open() }
        let source = sampler(state, batteryRead: { gate.block() })
        #expect(!source.allows(state.clock, stage: .beforeEnable))
        try wait { state.readCount == 1 }
        state.advance(1_000_000_001)
        for _ in 0..<10 { #expect(!source.allows(state.clock, stage: .monitoring)) }
        #expect(state.readCount == 1)
        state.hot()
        #expect(source.assessment(at: state.clock, stage: .monitoring).refusal == "currentThermalUnknownOrNonNominal")
        gate.open()
        try wait { source.assessment(at: state.clock, stage: .monitoring).observation != nil }
    }

    @Test func slowPlausibleSourceDoesNotBecomeFreshAtFinish() throws {
        let state = State()
        let source = sampler(state, batteryRead: { state.advance(200_000_001) })
        _ = source.assessment(at: state.clock, stage: .beforeEnable)
        try wait { source.assessment(at: state.clock, stage: .beforeEnable).observation != nil }
        #expect(source.assessment(at: state.clock, stage: .beforeEnable).refusal == "staleSlowOrRegressedRead")
    }

    @Test func thermalStallCannotValidateAgainstPreReadClock() throws {
        let state = State(); let gate = Gate()
        defer { gate.open() }
        let control = NSLock()
        var stallThermal = false
        let calls = NativeSafetySystemCalls(batteries: {
            state.readStarted()
            if state.readCount > 1 { gate.block() }
            return [["Type": "InternalBattery", "Is Present": true, "Current Capacity": 75,
                     "Max Capacity": 100, "Power Source State": "AC Power"]]
        }, lidProperty: { kCFBooleanFalse }, displays: { [1] }, displayFlags: { _ in
            NativeDisplayFlags(builtin: 1, online: 1, asleep: 0)
        }, thermal: {
            if control.withLock({ stallThermal }) { state.advance(200_000_001) }
            return .nominal
        })
        let source = NativeSafetySampler(systemCalls: calls, clock: { state.clock })
        try wait { source.allows(state.clock, stage: .beforeEnable) }
        state.advance(900_000_000)
        _ = source.assessment(at: state.clock, stage: .beforeEnable)
        try wait { state.readCount == 2 }
        control.withLock { stallThermal = true }
        let assessment = source.assessment(at: state.clock, stage: .beforeEnable)
        #expect(!assessment.allowed)
        #expect(assessment.refusal == "staleSlowOrRegressedRead")
        gate.open()
    }

    @Test(arguments: ["bootChanged", "regressed", "unavailable"])
    func assessmentResampleClockFaultNeverPermits(_ fault: String) throws {
        let state = State()
        let calls = NativeSafetySystemCalls(batteries: {
            [["Type": "InternalBattery", "Is Present": true, "Current Capacity": 75,
              "Max Capacity": 100, "Power Source State": "AC Power"]]
        }, lidProperty: { kCFBooleanFalse }, displays: { [1] }, displayFlags: { _ in
            NativeDisplayFlags(builtin: 1, online: 1, asleep: 0)
        }, thermal: { .nominal })
        let source = NativeSafetySampler(systemCalls: calls, clock: {
            guard state.clockFaultEnabled else { return state.clock }
            if fault == "unavailable" { throw BrokerFailure.environmentUnavailable }
            return BrokerClockSnapshot(bootID: fault == "bootChanged" ? "00000000-0000-0000-0000-000000000002" : state.clock.bootID,
                nowNanos: fault == "regressed" ? state.clock.nowNanos - 1 : state.clock.nowNanos)
        })
        try wait { source.allows(state.clock, stage: .beforeEnable) }
        state.enableClockFault()
        #expect(!source.allows(state.clock, stage: .beforeEnable))
    }

    @Test func cachedSafeSampleCannotMaskFreshCriticalThermal() throws {
        let state = State(); let source = sampler(state)
        try wait { source.allows(state.clock, stage: .beforeEnable) }
        state.hot()
        #expect(!source.allows(state.clock, stage: .monitoring))
    }

    @Test(arguments: [["--run"], ["--approve"], ["--readiness", "--run"]])
    func disabledLauncherRejectsAllActionFlagsWithoutSensorOrPowerCalls(_ flags: [String]) throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #if DEBUG
        let mode = "Debug"
        #else
        let mode = "Release"
        #endif
        let roots = [Bundle.main.bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
            package.appendingPathComponent(".build/\(mode.lowercased())"),
            package.appendingPathComponent(".build/out/Products/\(mode)")]
        let executable = try #require(roots.map { $0.appendingPathComponent("LidAttendedPreflight") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) })
        let child = Process(); let pipe = Pipe()
        child.executableURL = executable; child.arguments = flags; child.standardOutput = pipe
        defer {
            if child.isRunning { _ = kill(child.processIdentifier, SIGKILL); child.waitUntilExit() }
            try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close()
        }
        try child.run()
        try wait { !child.isRunning }
        child.waitUntilExit()
        try pipe.fileHandleForWriting.close()
        let read = try pipe.fileHandleForReading.readToEnd()
        let data = try #require(read)
        let decoded = try JSONSerialization.jsonObject(with: data)
        let report = try #require(decoded as? [String: Any])
        #expect(child.terminationStatus == 3)
        #expect(report["decision"] as? String == "nativeExecutionDisabled")
        #expect(report["nativeExecutionEnabled"] as? Bool == false)
        #expect(report["nativePowerCallsAttempted"] as? Bool == false)
        #expect(report["assessment"] == nil)
    }
}
