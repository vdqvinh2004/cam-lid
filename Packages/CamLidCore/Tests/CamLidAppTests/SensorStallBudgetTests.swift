import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

/// Spec 017 (User Story 2): each source has its own stall budget. The existing LiveSensorWorkerTests cover the
/// injected reader, where one duration applies to every source; these cover the hardware pass.
@Suite("Sensor stall budget per source")
struct SensorStallBudgetTests {
    @Test("a slow temperature read never marks the lid unknown")
    func slowTemperatureLeavesTheLidReadable() {
        let readings = openReadings(at: 10)
        let settled = LiveSensorProvider.settle(
            SensorPass(readings: readings, lidElapsed: 0.01, temperatureElapsed: 0.35), startedAt: 10)
        #expect(settled.lidObservation?.availability == "available")
        #expect(settled.lidObservation?.state == .open)
        #expect(settled.temperature.reasonCode == "slowSensorRead")
    }

    @Test("a slow lid call marks only the lid")
    func slowLidLeavesTheTemperatureAlone() {
        let readings = openReadings(at: 10)
        let settled = LiveSensorProvider.settle(
            SensorPass(readings: readings, lidElapsed: 0.3, temperatureElapsed: 0.01), startedAt: 10)
        #expect(settled.lidObservation?.availability == "error")
        #expect(settled.lidObservation?.reasonCode == "slowSensorRead")
        #expect(settled.temperature == readings.temperature)
    }

    @Test("the lid keeps the time its read started, not the time it finished")
    func lidIsStampedWithTheReadStart() {
        let settled = LiveSensorProvider.settle(
            SensorPass(readings: openReadings(at: 12), lidElapsed: 0.01, temperatureElapsed: 0.01), startedAt: 12)
        #expect(settled.lidObservation?.sampledAtMonotonic == 12)
    }

    @Test("the stall budget is 200 ms inclusive, and rejects anything not finite or negative")
    func budgetBoundary() {
        #expect(LiveSensorProvider.withinStallBudget(0.2))
        #expect(!LiveSensorProvider.withinStallBudget(0.2001))
        #expect(!LiveSensorProvider.withinStallBudget(-0.001))
        #expect(!LiveSensorProvider.withinStallBudget(.nan))
        #expect(!LiveSensorProvider.withinStallBudget(.infinity))
    }
}

private func openReadings(at time: Double) -> SensorReadings {
    SensorReadings(
        batteryPercent: 80,
        powerSource: .battery,
        thermalPressure: .nominal,
        cpuPercent: 10,
        lidState: .open,
        internalDisplayState: .awake,
        measuredAtMonotonic: time,
        lidObservation: LidObservation(state: .open, sampledAtMonotonic: time)
    )
}
