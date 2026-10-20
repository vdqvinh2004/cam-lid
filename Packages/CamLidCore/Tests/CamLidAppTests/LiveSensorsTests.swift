import Foundation
import CamLidCore
import Testing

@testable import CamLidApp

@Suite("Live sensor mapping (F12)")
struct LiveSensorsTests {
    @Test("thermal states map without inventing precision")
    func thermalMap() {
        #expect(ThermalMapper.map(.nominal) == .nominal)
        #expect(ThermalMapper.map(.fair) == .fair)
        #expect(ThermalMapper.map(.serious) == .serious)
        #expect(ThermalMapper.map(.critical) == .critical)
    }

    @Test("live read starts unknown without blocking and receives typed lid within two seconds")
    func liveReadIsNonblockingAndEventuallyTyped() {
        let provider = LiveSensorProvider()
        let start = ContinuousTime.now
        let initial = provider.read()
        #expect(ContinuousTime.now - start < 0.05)
        #expect(initial.measuredAtMonotonic == 0)
        #expect(initial.batteryPercent == nil)
        #expect(initial.powerSource == .unknown)
        #expect(initial.cpuPercent == nil)
        #expect(initial.lidState == .unknown)
        #expect(initial.internalDisplayState == .unknown)
        #expect(initial.lidObservation?.availability == "error")
        #expect(initial.lidObservation?.reasonCode == "samplePending")

        let deadline = ContinuousTime.now + 2
        var latest = initial
        while latest.measuredAtMonotonic == 0 && ContinuousTime.now < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            latest = provider.read()
        }
        #expect(latest.measuredAtMonotonic > 0)
        #expect(latest.measuredAtMonotonic <= ContinuousTime.now)
        #expect(ContinuousTime.now - latest.measuredAtMonotonic <= 2)
        #expect(latest.lidState == latest.lidObservation?.state)

        let observation = latest.lidObservation
        #expect(observation != nil)
        if let observation {
            switch observation.availability {
            case "available":
                #expect(observation.state == .open || observation.state == .closed)
                #expect(observation.sampledAtMonotonic != nil)
            case "error":
                #expect(observation.state == .unknown)
            default:
                Issue.record("Unexpected live lid availability: \(observation.availability)")
            }
        }
        if let battery = latest.batteryPercent {
            #expect(battery >= 0 && battery <= 100)
        }
    }
}

@Suite("CPU and internal display regressions")
struct SensorRegressionTests {
    @Test func sleepAdmissionSensorsCarryCurrentMonotonicSamples() {
        let startedAt = ContinuousTime.now
        let displays = LiveSensorProvider.displayObservation()
        let input = LiveSensorProvider.recentInputObservation()
        let finishedAt = ContinuousTime.now

        #expect(displays.sampledAtMonotonic >= startedAt)
        #expect(displays.sampledAtMonotonic <= finishedAt)
        #expect(input.sampledAtMonotonic >= startedAt)
        #expect(input.sampledAtMonotonic <= finishedAt)
        if let idle = input.idleSeconds {
            #expect(idle.isFinite && idle >= 0)
        }
    }

    @Test("the first CPU tick sample is unknown; valid aggregate deltas normalize to 0...100")
    func normalizedCPU() {
        var sampler = CPUTickSampler()
        #expect(sampler.sample([100, 100, 100, 100]) == nil)
        #expect(sampler.sample([125, 125, 150, 100]) == 50)
        #expect(sampler.sample([125, 125, 150, 100]) == nil)
        #expect(sampler.sample([1, 1, 1, 1]) == nil)
        #expect(sampler.sample(nil) == nil)
        #expect(sampler.sample([2, 2, 2, 2]) == nil)
    }
    @Test func internalDisplayAbsenceIsUnknown() {
        #expect(LiveSensorProvider.displayState([]) == .unknown)
        #expect(LiveSensorProvider.displayState([true]) == .asleep)
        #expect(LiveSensorProvider.displayState([true, false]) == .awake)
    }
}
