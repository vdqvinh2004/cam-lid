import Foundation

public enum NumericChoice {
    public static func presets(_ field: SettingsFieldError.Field) -> [Int] {
        switch field {
        case .timer: [0, 5, 10, 15, 30, 60, 120, 240, 480]
        case .completionDelay, .waitRetention: [0, 1, 2, 5, 10, 15, 30]
        case .batteryFloor: [10, 15, 20, 25, 30, 40, 50]
        case .batteryEntry: [20, 30, 40, 50, 60, 70, 80]
        case .batteryCap: [15, 30, 60, 120, 240]
        case .runCap: [15, 30, 60, 120, 240, 480]
        case .adapters: []
        }
    }
    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var ascii = ""
        for character in trimmed {
            guard character.unicodeScalars.count == 1,
                  let value = character.wholeNumberValue, (0...9).contains(value),
                  CharacterSet.decimalDigits.contains(character.unicodeScalars.first!) else { return nil }
            ascii += String(value)
        }
        return Int(ascii)
    }
    public static func label(_ value: Int, field: SettingsFieldError.Field) -> String {
        switch field {
        case .timer where value == 0: "∞ Infinite"
        case .completionDelay where value == 0: "Immediately"
        case .waitRetention where value == 0: "Do not retain"
        case .batteryFloor, .batteryEntry: "\(value)%"
        case .runCap where value >= 60 && value % 60 == 0,
             .timer where value >= 60 && value % 60 == 0: "\(value / 60) hr"
        default: "\(value) min"
        }
    }
}
