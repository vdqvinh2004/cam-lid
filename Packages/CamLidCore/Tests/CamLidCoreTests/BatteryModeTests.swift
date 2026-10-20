import Foundation
import Testing
@testable import CamLidCore

@Suite("Opt-in battery configuration and safety")
struct BatteryModeTests {
    private func health(_ battery: Double? = 60, power: PowerSource = .battery,
        thermal: ThermalPressure = .nominal) throws -> HealthSnapshot {
        try HealthSnapshot(batteryPercent: battery, powerSource: power, thermalPressure: thermal, lidState: .open)
    }

    @Test func defaultsAndLegacyDecodeNeverOptIn() throws {
        let original = try Configuration(batteryFloorPercent: 50)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["batteryModeAllowed", "batteryEntryPercent", "batteryCapMinutes"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.chargingOnly && !decoded.batteryModeAllowed)
        #expect(decoded.batteryEntryPercent == 51 && decoded.batteryCapMinutes == 60)
        #expect(decoded == original)
        #expect(try Configuration().batteryEntryPercent == 40)
    }

    @Test func invalidExtremeLegacyFloorDoesNotOverflowDefaultEntry() throws {
        #expect(throws: ConfigError.self) { try Configuration(batteryFloorPercent: Int.max) }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration())) as? [String: Any])
        object["batteryFloorPercent"] = Int.max
        object.removeValue(forKey: "batteryEntryPercent")
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(throws: ConfigError.self) { try decoded.validate() }
    }

    @Test func patchMigrationAndCodablePreserveExplicitValues() throws {
        let patch = try ConfigPatch(jsonDictionary: ["chargingOnly": false, "batteryModeAllowed": true,
            "batteryEntryPercent": 55, "batteryCapMinutes": 90])
        let applied = try Configuration().applying(patch)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(applied)) == applied)
        let migrated = try Configuration.migrate(from: ["chargingOnly": false, "batteryModeAllowed": true,
            "batteryEntryPercent": 55, "batteryCapMinutes": 90, "mode": "auto", "closedLidOptIn": true])
        #expect(migrated.batteryModeAllowed && migrated.batteryEntryPercent == 55 && migrated.batteryCapMinutes == 90)
        #expect(migrated.mode == .off && !migrated.closedLidOptIn)
        let clamped = try Configuration.migrate(from: ["batteryFloorPercent": 50, "batteryEntryPercent": 20, "batteryCapMinutes": 999])
        #expect(clamped.batteryEntryPercent == 51 && clamped.batteryCapMinutes == 240)
    }

    @Test func strictPatchRejectsWrongTypesAndInvalidBounds() throws {
        for value: Any in [1, "true", NSNull()] {
            #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: ["batteryModeAllowed": value]) }
            #expect(throws: ConfigError.self) { try Configuration.migrate(from: ["batteryModeAllowed": value]) }
        }
        for key in ["batteryEntryPercent", "batteryCapMinutes"] {
            for value: Any in [true, "40", NSNull(), 20.5] {
                #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: [key: value]) }
            }
        }
        for (key, value) in [("batteryEntryPercent", 19), ("batteryEntryPercent", 81),
                              ("batteryCapMinutes", 14), ("batteryCapMinutes", 241), ("batteryEntryPercent", 20)] {
            #expect(throws: ConfigError.self) { try Configuration().applying(ConfigPatch(jsonDictionary: [key: value])) }
        }
        #expect(throws: ConfigError.self) { try Configuration(batteryFloorPercent: 40, batteryEntryPercent: 40) }
    }

    @Test func entryNeedsBothSwitchesKnownBatteryAndThreshold() throws {
        let enabled = try Configuration(chargingOnly: false, batteryModeAllowed: true)
        #expect(enabled.batteryEntryRefusal(health: try health(40)) == nil)
        #expect(enabled.batteryEntryRefusal(health: try health(39)) == "batteryEntryLow")
        #expect(enabled.batteryEntryRefusal(health: try health(nil)) == "batteryUnknown")
        #expect(enabled.batteryEntryRefusal(health: try health(power: .unknown)) == "powerUnknown")
        #expect(try Configuration(chargingOnly: false).batteryEntryRefusal(health: health()) == "notCharging")
        #expect(try Configuration(batteryModeAllowed: true).batteryEntryRefusal(health: health()) == "notCharging")
        #expect(try Configuration().batteryEntryRefusal(health: health(nil, power: .ac)) == nil)
    }

    @Test func monitoringPreservesFloorUnknownThermalAndImmediateRevocation() throws {
        let enabled = try Configuration(chargingOnly: false, batteryModeAllowed: true)
        var policy = SafetyPolicy()
        #expect(policy.evaluate(health: try health(30), config: enabled, cpuStop: false, now: 100) == .clear)
        let revoked = try enabled.applying(ConfigPatch(jsonDictionary: ["batteryModeAllowed": false]))
        #expect(policy.evaluate(health: try health(), config: revoked, cpuStop: false, now: 101).reasons.contains("notCharging"))
        for (snapshot, reason) in [(try health(19), "batteryFloor"), (try health(nil), "batteryUnknown"),
                                   (try health(60, power: .unknown), "powerUnknown"),
                                   (try health(60, thermal: .critical), "thermalCritical")] {
            var fresh = SafetyPolicy()
            #expect(fresh.evaluate(health: snapshot, config: enabled, cpuStop: false, now: 200).reasons.contains(reason))
        }
    }

    @Test func batteryCapsEveryModeIncludingInfinite() throws {
        let config = try Configuration(chargingOnly: false, batteryModeAllowed: true, batteryCapMinutes: 60,
            runCapMinutes: 120, timerMinutes: 0)
        for mode in [RequestedMode.auto, .timed, .manual] {
            #expect(config.sessionDurationMinutes(for: mode, powerSource: .battery) == 60)
        }
        #expect(config.sessionDurationMinutes(for: .timed, powerSource: .ac) == nil)
        #expect(config.sessionDurationMinutes(for: .manual, powerSource: .ac) == nil)
        let shorter = try config.applying(ConfigPatch(jsonDictionary: ["runCapMinutes": 30, "timerMinutes": 15]))
        #expect(shorter.sessionDurationMinutes(for: .auto, powerSource: .battery) == 30)
        #expect(shorter.sessionDurationMinutes(for: .timed, powerSource: .battery) == 15)
    }
}
