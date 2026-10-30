import CamLidCore
import IOKit.ps
import Testing

@testable import CamLidApp

struct BatterySourceSelectionTests {
    private func source(_ type: String, state: String = kIOPSACPowerValue,
                        current: Double = 80) -> [String: Any] {
        [kIOPSTypeKey: type, kIOPSPowerSourceStateKey: state,
         kIOPSCurrentCapacityKey: current, kIOPSMaxCapacityKey: 100.0,
         kIOPSIsChargingKey: false]
    }

    @Test func externalSourceCannotOverrideInternalBattery() {
        let external = source(kIOPSUPSType, current: 100)
        let internalBattery = source(kIOPSInternalBatteryType, state: kIOPSBatteryPowerValue, current: 35)
        for descriptions in [[external, internalBattery], [internalBattery, external]] {
            let (battery, power) = LiveSensorProvider.batteryAndPower(from: descriptions)
            #expect(battery == 35)
            #expect(power == .battery)
        }
    }

    @Test func absentOrAmbiguousInternalBatteryIsUnknown() {
        let internalBattery = source(kIOPSInternalBatteryType)
        for descriptions in [[], [source(kIOPSUPSType)], [internalBattery, internalBattery],
                             [[kIOPSPowerSourceStateKey: kIOPSACPowerValue]]] {
            let (battery, power) = LiveSensorProvider.batteryAndPower(from: descriptions)
            #expect(battery == nil)
            #expect(power == .unknown)
        }
    }

    @Test func acDoesNotRequireChargingAndMissingStateIsUnknown() {
        var internalBattery = source(kIOPSInternalBatteryType)
        let (battery, power) = LiveSensorProvider.batteryAndPower(from: [internalBattery])
        #expect(battery == 80)
        #expect(power == .ac)
        internalBattery.removeValue(forKey: kIOPSPowerSourceStateKey)
        #expect(LiveSensorProvider.batteryAndPower(from: [internalBattery]).1 == .unknown)
    }
}
