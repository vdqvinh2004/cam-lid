import Foundation
import Dispatch
import CamLidCore
import Testing

@testable import CamLidApp

@Suite("Bounded live sensor worker")
struct LiveSensorWorkerTests {
    @Test("slow hardware reads return immediately and never stack worker jobs")
    func slowReaderIsBounded() {
        let clock = SensorTestClock(100)
        let gate = DispatchSemaphore(value: 0)
        let calls = SensorReadCounters()
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { .nominal },
            reader: { startedAt in
                let callNumber = calls.begin()
                defer { calls.end() }
                if callNumber == 1 { _ = gate.wait(timeout: .now() + 2) }
                return sensorReadings(at: startedAt, battery: 73)
            }
        )

        let firstStarted = ContinuousTime.now
        let first = provider.read()
        let secondStarted = ContinuousTime.now
        let second = provider.read()
        #expect(ContinuousTime.now - firstStarted < 0.05)
        #expect(ContinuousTime.now - secondStarted < 0.05)
        #expect(first.batteryPercent == nil)
        #expect(second.batteryPercent == nil)
        #expect(first.lidObservation?.state == .unknown)
        #expect(second.lidObservation?.state == .unknown)

        waitUntil { calls.snapshot().starts == 1 }
        clock.set(110)
        _ = provider.read()
        _ = provider.read()
        #expect(calls.snapshot().starts == 1)
        #expect(calls.snapshot().maximumConcurrent == 1)

        gate.signal()
        waitUntil { provider.read().batteryPercent == 73 }
        let completed = provider.read()
        #expect(completed.measuredAtMonotonic >= 100)
        #expect(calls.snapshot().maximumConcurrent == 1)
    }

    @Test("critical thermal sample bypasses a blocked worker and keeps its own time")
    func criticalThermalIsImmediate() {
        let clock = SensorTestClock(200)
        let thermal = SensorTestThermal()
        let gate = DispatchSemaphore(value: 0)
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { thermal.value() },
            reader: { startedAt in
                _ = gate.wait(timeout: .now() + 2)
                return sensorReadings(at: startedAt, battery: 61)
            }
        )

        _ = provider.read()
        thermal.set(.critical)
        clock.set(200.4)
        let result = provider.read()
        #expect(result.thermalPressure == .critical)
        #expect(result.criticalThermalSampledAtMonotonic == 200.4)
        #expect(result.batteryPercent == nil)
        gate.signal()
    }

    @Test("hardware sampling is rate limited to one start per second")
    func samplingRateIsBounded() {
        let clock = SensorTestClock(250)
        let calls = SensorReadCounters()
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { .nominal },
            reader: { startedAt in
                calls.begin()
                defer { calls.end() }
                return sensorReadings(at: startedAt, battery: 54)
            }
        )

        _ = provider.read()
        waitUntil { calls.snapshot().starts == 1 }
        clock.set(250.999)
        _ = provider.read()
        _ = provider.read()
        #expect(calls.snapshot().starts == 1)

        clock.set(251)
        _ = provider.read()
        waitUntil { calls.snapshot().starts == 2 }
        #expect(calls.snapshot().maximumConcurrent == 1)
    }

    @Test("slow lid completion becomes unknown")
    func slowLidReadIsUnknown() {
        let clock = SensorTestClock(300)
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { .nominal },
            reader: { startedAt in
                clock.set(startedAt + 0.25)
                return sensorReadings(at: startedAt, battery: 88)
            }
        )

        _ = provider.read()
        waitUntil { provider.read().batteryPercent == 88 }
        let slow = provider.read()
        #expect(slow.measuredAtMonotonic == 300)
        #expect(slow.lidState == .unknown)
        #expect(slow.lidObservation?.availability == "error")
        #expect(slow.lidObservation?.reasonCode == "slowSensorRead")
    }

    @Test("cached lid keeps the source start timestamp and expires after five seconds")
    func lidFreshnessUsesSourceStart() {
        let clock = SensorTestClock(400)
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { .nominal },
            reader: { startedAt in sensorReadings(at: startedAt, battery: 88) }
        )

        _ = provider.read()
        waitUntil { provider.read().batteryPercent == 88 }
        let cached = provider.read()
        #expect(cached.measuredAtMonotonic == 400)
        #expect(cached.lidObservation?.sampledAtMonotonic == 400)

        // A later GUI poll reuses the old timestamp; it cannot make the cached
        // lid look newly sampled.
        clock.set(406)
        let stale = provider.read()
        #expect(stale.measuredAtMonotonic == 400)
        #expect(stale.lidState == .unknown)
        #expect(stale.lidObservation?.availability == "stale")
    }
}

private func sensorReadings(at time: Double, battery: Double) -> SensorReadings {
    SensorReadings(
        batteryPercent: battery,
        powerSource: .battery,
        thermalPressure: .nominal,
        cpuPercent: 42,
        lidState: .open,
        internalDisplayState: .awake,
        measuredAtMonotonic: time,
        lidObservation: LidObservation(state: .open, sampledAtMonotonic: time)
    )
}

private func waitUntil(
    timeout: Double = 1.5,
    condition: () -> Bool
) {
    let deadline = ContinuousTime.now + timeout
    while !condition(), ContinuousTime.now < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
}

private final class SensorTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double

    init(_ time: Double) { self.time = time }

    func now() -> Double {
        lock.lock(); defer { lock.unlock() }
        return time
    }

    func set(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        time = value
    }
}

private final class SensorTestThermal: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ThermalPressure = .nominal

    func value() -> ThermalPressure {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func set(_ value: ThermalPressure) {
        lock.lock(); defer { lock.unlock() }
        current = value
    }
}

private final class SensorReadCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var active = 0
    private var maximumConcurrent = 0

    @discardableResult
    func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        starts += 1
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        return starts
    }

    func end() {
        lock.lock(); defer { lock.unlock() }
        active -= 1
    }

    func snapshot() -> (starts: Int, maximumConcurrent: Int) {
        lock.lock(); defer { lock.unlock() }
        return (starts, maximumConcurrent)
    }
}
