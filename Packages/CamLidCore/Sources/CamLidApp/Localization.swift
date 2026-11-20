import Foundation
import Observation

/// Spec 028: the language CamLid shows. System follows macOS; English and Vietnamese are fixed choices.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system, english, vietnamese
}

/// Observed storage: a SwiftUI body that calls `tr` redraws when the language changes.
@Observable final class LanguageState: @unchecked Sendable {
    var isVietnamese = false
}

/// Keys are the English text. The Vietnamese values come from `Localizable.xcstrings`, which SwiftPM compiles into the
/// package's `vi.lproj`. CamLid chooses the language itself (Settings › General), so it does not use the system lookup.
enum Localization {
    nonisolated(unsafe) static let state = LanguageState()

    /// Tests scope a language to their own task with `$languageOverride.withValue`, so no other test reads it.
    @TaskLocal static var languageOverride: Bool? = nil

    /// True while Vietnamese is shown. The main app sets it from the saved choice; the utility process sets it from its state.
    static var isVietnamese: Bool {
        get { languageOverride ?? state.isVietnamese }
        set { state.isVietnamese = newValue }
    }

    /// Whether a saved choice shows Vietnamese now. System follows the first preferred language of macOS.
    static func resolve(_ choice: AppLanguage) -> Bool {
        switch choice {
        case .vietnamese: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("vi") ?? false
        }
    }

    /// The formatting locale for dates and numbers (spec 028 FR-005), so they follow the chosen language.
    static var locale: Locale { isVietnamese ? Locale(identifier: "vi_VN") : Locale(identifier: "en_US") }

    static func text(_ key: String) -> String { text(key, vietnamese: isVietnamese) }

    /// The text in a given language. Tests use it, so they never change the shared language.
    static func text(_ key: String, vietnamese: Bool) -> String {
        guard vietnamese, let bundle = vietnameseBundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// The `vi.lproj` that SwiftPM builds from Localizable.xcstrings. A key without a value falls back to its English text.
    static let vietnameseBundle: Bundle? = Bundle.module.path(forResource: "vi", ofType: "lproj").flatMap { Bundle(path: $0) }

    /// The catalogue as pairs of templates, one per entry: the English key and its Vietnamese value, from the strings file.
    nonisolated(unsafe) static let catalogue: [(english: CatalogueTemplate, vietnamese: CatalogueTemplate)] = {
        guard let path = vietnameseBundle?.path(forResource: "Localizable", ofType: "strings"),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else { return [] }
        return table.sorted { $0.key < $1.key }
            .map { (english: CatalogueTemplate($0.key), vietnamese: CatalogueTemplate($0.value)) }
    }()

    /// Stored messages (notices, status lines, outcomes) are kept as English, the catalogue's key text, and shown in the current
    /// language where they are drawn, so a switch changes them too (spec 028 FR-002). Text the catalogue does not know is shown as it is.
    static func display(_ message: String) -> String {
        guard isVietnamese else { return message }
        if let value = vietnameseByKey[message] { return value }
        var best: (score: Int, text: String)?
        for entry in catalogue where !entry.english.specifiers.isEmpty {
            guard let arguments = entry.english.arguments(in: message), let filled = entry.vietnamese.filled(arguments) else { continue }
            if best.map({ entry.english.literalLength > $0.score }) ?? true { best = (entry.english.literalLength, filled) }
        }
        return best?.text ?? message
    }

    /// The Vietnamese value of each English key that has no placeholders, for exact lookups.
    nonisolated(unsafe) static let vietnameseByKey: [String: String] = Dictionary(uniqueKeysWithValues: catalogue
        .filter { $0.english.specifiers.isEmpty }
        .map { ($0.english.literals[0], $0.vietnamese.literals[0]) })
}

/// A catalogue text split at its placeholders (`%@`, `%lld`, `%.1f`): `literals` are the parts between them, `specifiers` the
/// placeholders in order. A stored message is matched against these templates when it is shown (`Localization.display`).
struct CatalogueTemplate {
    nonisolated(unsafe) static let specifier = try! NSRegularExpression(pattern: #"%(?:\.\d+f|lld|ld|d|@)"#)

    let literals: [String]
    let specifiers: [String]
    private let matcher: NSRegularExpression?

    init(_ text: String) {
        let ns = text as NSString
        var literals: [String] = []
        var specifiers: [String] = []
        var cursor = 0
        for match in Self.specifier.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            literals.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            specifiers.append(ns.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        literals.append(ns.substring(from: cursor))
        self.literals = literals
        self.specifiers = specifiers
        matcher = specifiers.isEmpty ? nil : try? NSRegularExpression(
            pattern: #"\A"# + literals.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "(.*?)") + #"\z"#,
            options: [.dotMatchesLineSeparators])
    }

    /// The characters that are not placeholders. An exact key has the most, so it wins over a template that also fits.
    var literalLength: Int { literals.reduce(0) { $0 + $1.count } }

    /// The text with `arguments` in place of the placeholders, or nil when their count differs.
    func filled(_ arguments: [String]) -> String? {
        guard arguments.count == specifiers.count else { return nil }
        return zip(literals, arguments + [""]).map { $0 + $1 }.joined()
    }

    /// The arguments that fill this template to give `text`, or nil when `text` is not an instance of it.
    func arguments(in text: String) -> [String]? {
        guard let matcher else { return text == literals[0] ? [] : nil }
        let ns = text as NSString
        guard let match = matcher.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
    }
}

/// The text for an English key in the current language.
func tr(_ key: String) -> String { Localization.text(key) }

/// A message with placeholders (`%@` for text, `%lld` for whole numbers) filled in the current language's order.
func trf(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Localization.text(key), arguments: arguments)
}
