import Testing
import Foundation
import CamLidCore

@testable import CamLidApp

/// Qualified HID die selection (Mac16,12/macOS 27): hottest "PMU tdie*" sensor in
/// (0, 125)°C. Composites, battery/NAND/ALS entries, unpopulated negatives and
/// non-PMU names are never selected.
struct TemperatureReaderTests {
    @Test func hottestValidDieWins() {
        let services = [
            (name: "gas gauge battery", value: 32.0),
            (name: "PMU tdie2", value: 37.89),
            (name: "PMU tdie6", value: 42.21),
            (name: "PMU tdev1", value: -22.25),
            (name: "NAND CH0 temp", value: 37.0),
        ]
        let best = HIDThermalReader.selectHottestDie(in: services)
        #expect(best?.name == "PMU tdie6")
        #expect(best?.value == 42.21)
    }

    @Test func frozenCompositeAndInvalidNeverSelected() {
        // "PMU tcal" reads stale via polling copies and is excluded by name rule.
        let services = [
            (name: "PMU tcal", value: 51.82),
            (name: "PMU2 tcal", value: 51.82),
            (name: "PMU tdie1", value: -22.0),
            (name: "als-temp", value: 25.0),
        ]
        #expect(HIDThermalReader.selectHottestDie(in: services) == nil)
    }

    @Test func emptyAndOutOfRangeYieldNil() {
        #expect(HIDThermalReader.selectHottestDie(in: []) == nil)
        #expect(HIDThermalReader.selectHottestDie(in: [(name: "PMU tdie1", value: 0.0)]) == nil)
        #expect(HIDThermalReader.selectHottestDie(in: [(name: "PMU tdie1", value: 200.0)]) == nil)
        #expect(HIDThermalReader.selectHottestDie(in: [(name: "PMU tdie1", value: .nan)]) == nil)
        #expect(HIDThermalReader.isDieSensor(named: "PMU2 tdie14"))
        #expect(!HIDThermalReader.isDieSensor(named: "PMU tdev3"))
        #expect(!HIDThermalReader.isDieSensor(named: "TC0P"))
    }

    @Test func injectedTemperatureFlowsThroughWorker() {
        let clock = TempTestClock(500)
        let fixture = TemperatureObservation(
            valueCelsius: 41.5, sensorID: "PMU tdie6", displayName: "CPU die (hottest)",
            source: HIDThermalReader.source, sampledAtMonotonic: 500, availability: "available")
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { .nominal },
            reader: { startedAt in
                var readings = tempSensorReadings(at: startedAt)
                readings.temperature = fixture
                return readings
            }
        )
        _ = provider.read()
        tempWaitUntil(timeout: 2) { provider.read().temperature.availability == "available" }
        let result = provider.read()
        #expect(result.temperature.valueCelsius == 41.5)
        #expect(result.temperature.sensorID == "PMU tdie6")
        #expect(result.temperature.source == HIDThermalReader.source)
    }

    @Test func slowWorkerMapsTemperatureToError() {
        let clock = TempTestClock(600)
        let provider = LiveSensorProvider(
            sampleInterval: 1,
            clock: { clock.now() },
            thermalReader: { .nominal },
            reader: { startedAt in
                // The read takes 350 ms on the worker's clock; stall budgets are measured on that clock.
                clock.set(startedAt + 0.35)
                var readings = tempSensorReadings(at: startedAt)
                readings.temperature = TemperatureObservation(
                    valueCelsius: 41.5, sensorID: "PMU tdie6", displayName: "CPU die (hottest)",
                    source: HIDThermalReader.source, sampledAtMonotonic: startedAt, availability: "available")
                return readings
            }
        )
        _ = provider.read()
        tempWaitUntil(timeout: 2) { provider.read().temperature.availability == "error" }
        #expect(provider.read().temperature.availability == "error")
        #expect(provider.read().temperature.valueCelsius == nil)
    }

    // Explicit opt-in: live silicon on the qualified host only (Mac16,12/macOS 27).
    // Skipped in canonical runs; run separately with CAMLID_LIVE_TEMP_PROBE=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAMLID_LIVE_TEMP_PROBE"] == "1"))
    func liveDieReadingIsAvailableAndSane() {
        let observation = TemperatureReader.read()
        #expect(observation.availability == "available")
        let value = try? #require(observation.valueCelsius)
        #expect(value ?? -1 > 0 && value ?? 999 < 125)
        #expect(observation.sensorID?.hasPrefix("PMU") == true)
        #expect(observation.displayName == "CPU die (hottest)")
        #expect(observation.source == HIDThermalReader.source)
        #expect(observation.sampledAtMonotonic ?? -1 >= 0)
    }
}

private func tempSensorReadings(at time: Double) -> SensorReadings {
    SensorReadings(
        batteryPercent: 73,
        powerSource: .battery,
        thermalPressure: .nominal,
        cpuPercent: 42,
        lidState: .open,
        internalDisplayState: .awake,
        measuredAtMonotonic: time,
        lidObservation: LidObservation(state: .open, sampledAtMonotonic: time)
    )
}

private func tempWaitUntil(timeout: Double = 1.5, condition: () -> Bool) {
    let deadline = ContinuousTime.now + timeout
    while !condition(), ContinuousTime.now < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
}

private final class TempTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double

    init(_ time: Double) { self.time = time }

    func set(_ time: Double) {
        lock.lock(); defer { lock.unlock() }
        self.time = time
    }

    func now() -> Double {
        lock.lock(); defer { lock.unlock() }
        return time
    }
}
