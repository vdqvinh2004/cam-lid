import Testing
import CamLidCore
@testable import CamLidApp
struct NumericChoiceTests {
    @Test func shortTimersRemainAvailableBelowAFifteenMinuteSafetyLimit() {
        let choices = NumericChoice.presets(.timer).filter { $0 > 0 && $0 <= 15 }
        #expect(choices == [5, 10, 15])
    }
    @Test func integerParsingRejectsIncompleteAndAcceptsDecimalDigits() {
        for invalid in ["", "-1", "+1", "1.5", "Ⅳ", "²", "999999999999999999999999999"] { #expect(NumericChoice.parse(invalid) == nil) }
        #expect(NumericChoice.parse(" ١٢ ") == 12)
        #expect(NumericChoice.parse("５") == 5)
    }
    @Test @MainActor func presetsValidateAndCustomValuesRemainVisible() throws {
        let fields: [SettingsFieldError.Field] = [.timer, .completionDelay, .waitRetention, .batteryFloor, .batteryEntry, .batteryCap, .runCap]
        for field in fields {
            let configuration = try Configuration(batteryFloorPercent: field == .batteryEntry ? 10 : 20,
                batteryEntryPercent: field == .batteryFloor ? 80 : 40)
            let editor = SettingsEditor(configuration: configuration, revision: 1)
            editor.configureAutosave { _, revision in .saved(revision: revision + 1) }
            for value in NumericChoice.presets(field) {
                editor.selectPreset(value, field: field)
                #expect(editor.errors.isEmpty && !editor.customFields.contains(field))
            }
            editor.chooseCustom(field)
            #expect(editor.customFields.contains(field))
        }
        let custom = SettingsEditor(configuration: try Configuration(completionDelayMinutes: 7, waitRetentionMinutes: 3, batteryFloorPercent: 23, runCapMinutes: 17), revision: 1)
        #expect(custom.customFields.count == 5 && custom.customFields.contains(.timer))
    }

    @Test @MainActor func outsideChangeTogglesCustomField() throws {
        let editor = SettingsEditor(configuration: try Configuration(completionDelayMinutes: 7), revision: 1)
        #expect(editor.customFields.contains(.completionDelay))
        let preset = NumericChoice.presets(.completionDelay)[0]
        editor.receive(configuration: try Configuration(completionDelayMinutes: preset), revision: 2)
        #expect(!editor.customFields.contains(.completionDelay) && editor.numbers[.completionDelay] == String(preset))
        editor.receive(configuration: try Configuration(completionDelayMinutes: 7), revision: 3)
        #expect(editor.customFields.contains(.completionDelay))
    }
}
