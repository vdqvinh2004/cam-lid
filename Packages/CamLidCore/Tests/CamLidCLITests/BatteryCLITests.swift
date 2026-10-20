import Foundation
import Testing
import CamLidCore
import CamLidCLI

@Suite("Battery CLI contracts remain bounded and opt-in")
struct BatteryCLITests {
    @Test func batteryKeysAcceptedAndWrongTypesRefused() throws {
        var context = CommandContext(files: [
            "valid.json": "{\"chargingOnly\":false,\"batteryModeAllowed\":true,\"batteryEntryPercent\":50,\"batteryCapMinutes\":30}",
            "bad.json": "{\"batteryModeAllowed\":1}",
            "null.json": "{\"batteryCapMinutes\":null}",
        ])
        let valid = dispatch(["config", "set", "--file", "valid.json"], context: &context)
        #expect(valid.exitCode == 0)
        #expect(context.config.batteryModeAllowed && context.config.batteryEntryPercent == 50 && context.config.batteryCapMinutes == 30)
        for path in ["bad.json", "null.json"] {
            #expect(dispatch(["config", "set", "--file", path], context: &context).exitCode == 2)
        }
    }

    @Test func startHonorsEntryAndCapsInfinite() throws {
        var context = CommandContext()
        context.config = try Configuration(chargingOnly: false, batteryModeAllowed: true)
        context.health = try HealthSnapshot(batteryPercent: 39, powerSource: .battery, thermalPressure: .nominal, lidState: .open)
        #expect(dispatch(["start", "--mode", "timed", "--duration", "infinite"], context: &context).exitCode == 3)
        #expect(context.session == nil)
        context.health = try HealthSnapshot(batteryPercent: 40, powerSource: .battery, thermalPressure: .nominal, lidState: .open)
        let result = dispatch(["start", "--mode", "timed", "--duration", "infinite"], context: &context)
        #expect(result.exitCode == 0)
        #expect(context.session?.capDeadlineMonotonic == context.nowMonotonic + 3_600)
        let object = try jsonDict(result)
        #expect(object["durationUnlimited"] as? Bool == false && object["capApplied"] as? Bool == true)
    }
}
