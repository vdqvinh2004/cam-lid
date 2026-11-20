import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// Spec 028 (T013, T030, T031): every catalogue key has a Vietnamese value, the code uses only catalogue keys, the language switch
/// changes the shown text, and no interface string is left outside `tr`. The checks read the source tree next to this file.
@Suite("Vietnamese interface", .serialized)
struct LocalizationTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CamLidApp")

    private static func swiftSources() throws -> [(name: String, text: String)] {
        try FileManager.default.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// The catalogue keys: the English text, with the escapes of the source file turned into the characters they stand for.
    private static func catalogue() throws -> [String: String] {
        let url = sourceRoot.appendingPathComponent("Resources/Localizable.xcstrings")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        var values: [String: String] = [:]
        for (key, entry) in strings {
            let unit = (entry["localizations"] as? [String: Any])
                .flatMap { $0["vi"] as? [String: Any] }
                .flatMap { $0["stringUnit"] as? [String: Any] }
            values[key] = unit?["value"] as? String ?? ""
        }
        return values
    }

    private static func unescaped(_ literal: String) -> String {
        literal.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
    }

    @Test func everyKeyHasAVietnameseValue() throws {
        let values = try Self.catalogue()
        #expect(values.count > 600)
        #expect(values.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.isEmpty)
    }

    @Test func everyTranslatedLiteralIsInTheCatalogue() throws {
        let keys = Set(try Self.catalogue().keys)
        let pattern = try NSRegularExpression(pattern: #"\btrf?\("((?:[^"\\]|\\.)*)""#)
        var missing: [String] = []
        for source in try Self.swiftSources() {
            let text = source.text as NSString
            for match in pattern.matches(in: source.text, range: NSRange(location: 0, length: text.length)) {
                let key = Self.unescaped(text.substring(with: match.range(at: 1)))
                if !keys.contains(key) { missing.append("\(source.name): \(key)") }
            }
        }
        #expect(missing.isEmpty, "Keys missing from Localizable.xcstrings: \(missing)")
    }

    @Test func noInterfaceLiteralIsLeftOutsideTr() throws {
        // Language names are shown in their own language, a bare symbol such as × has no words, and "Helper" stays English (spec 028 D3).
        let allowed: Set<String> = ["English", "Tiếng Việt", "×", "Helper", "CamLid"]
        let pattern = try NSRegularExpression(pattern:
            #"\b(?:Text|Button|Label|Toggle|Picker|Section|DisclosureGroup|LabeledContent|NSMenuItem|ValueRow|addButton|addItem)\((?:[Tt]itle:\s*|with[Tt]itle:\s*)?"((?:[^"\\]|\\.)*)""#
            + #"|\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue)\(\s*"((?:[^"\\]|\\.)*)""#)
        var left: [String] = []
        for source in try Self.swiftSources() {
            for line in source.text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let text = String(line) as NSString
                for match in pattern.matches(in: String(line), range: NSRange(location: 0, length: text.length)) {
                    guard let found = [1, 2].map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { continue }
                    let literal = text.substring(with: found)
                    // Interpolated values are data, so only the words around them count.
                    let words = literal.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "", options: .regularExpression)
                    guard words.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil,
                          !allowed.contains(literal) else { continue }
                    left.append("\(source.name): \(literal)")
                }
            }
        }
        #expect(left.isEmpty, "Interface text outside tr(): \(left)")
    }

    @Test func theLanguageChoiceChangesTheShownText() {
        #expect(Localization.text("Settings", vietnamese: false) == "Settings")
        #expect(Localization.text("Settings", vietnamese: true) == "Cài đặt")
        #expect(String(format: Localization.text("Step %lld of %lld", vietnamese: true), 1, 6) == "Bước 1 trên 6")
        #expect(Localization.resolve(.english) == false && Localization.resolve(.vietnamese) == true)
    }

    /// Vietnamese is scoped to this test only. The agent state stays a code (`camlid status` prints it), and the completion check
    /// that decides whether a Mac sleeps after agent work reads that code, so both must hold in either language.
    @Test @MainActor func machineOutputAndSafetyChecksStayEnglishInVietnamese() throws {
        try Localization.$languageOverride.withValue(true) {
            let badge = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1, observationKnown: false)
            #expect(badge.observedState == "Unknown")
            let json = String(decoding: try JSONEncoder().encode(badge), as: UTF8.self)
            #expect(json.contains("\"observedState\":\"Unknown\""))
            #expect(AppCoordinator.badgesLeaveCompletionUnproven([badge], activityClassified: { _ in true }))
        }
    }

    /// The Dashboard marks an unknown thermal or lid reading for attention by its code, whatever the language shows.
    @Test @MainActor func dashboardAttentionFollowsTheCodeInEitherLanguage() {
        for vietnamese in [false, true] {
            Localization.$languageOverride.withValue(vietnamese) {
                let rows = DashboardMetric.from(nil)
                #expect(rows.first { $0.id == "thermal" }?.attention == true)
                #expect(rows.first { $0.id == "lid" }?.attention == true)
            }
        }
    }

    /// The control status (`camlid status`) must carry agent states as codes in Vietnamese mode too (spec 028 FR-006).
    @Test @MainActor func controlStatusKeepsAgentStatesAsCodesInVietnamese() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        try await Localization.$languageOverride.withValue(true) {
            let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
            let status = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
            let rows = try #require(status["agentDetection"] as? [[String: Any]])
            let codes: Set<String> = ["Unknown", "Not detected", "Active", "Waiting", "Inactive"]
            let states = rows.compactMap { $0["observedState"] as? String }
            #expect(!states.isEmpty && states.allSatisfy { codes.contains($0) }, "observedState values: \(Set(states))")
        }
    }

    /// Owner's rename (2026-11-20): the mode names are Tự động and Hẹn giờ in Vietnamese, and English keeps Auto and Timed.
    @Test func theModeNamesAreTheVietnameseOnesInVietnamese() {
        #expect(Localization.text("Auto", vietnamese: true) == "Tự động")
        #expect(Localization.text("Timed", vietnamese: true) == "Hẹn giờ")
        #expect(Localization.text("Auto", vietnamese: false) == "Auto")
        #expect(Localization.text("Timed", vietnamese: false) == "Timed")
    }

    /// No Vietnamese text shows the English mode names, and the timer is always "hẹn giờ" (never "bộ hẹn giờ").
    @Test func vietnameseTextNeverShowsTheEnglishModeNames() throws {
        let english = try NSRegularExpression(pattern: #"\b(Auto|Timed|timer)\b|bộ hẹn giờ"#, options: [.caseInsensitive])
        let found = try Self.catalogue().filter { _, value in
            english.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) != nil
        }.keys.sorted()
        #expect(found.isEmpty, "Vietnamese values still show English mode names or 'bộ hẹn giờ': \(found)")
    }

    /// A mode name reaches the screen only through `tr` or `trf`, so the Vietnamese name applies everywhere.
    @Test func modeNamesReachTheScreenOnlyThroughTr() throws {
        let bare = try NSRegularExpression(pattern: #"(?<!tr\()(?<!trf\()"(Auto|Timed)""#)
        var found: [String] = []
        for source in try Self.swiftSources() {
            for line in source.text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let text = String(line) as NSString
                if bare.firstMatch(in: String(line), range: NSRange(location: 0, length: text.length)) != nil {
                    found.append("\(source.name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(found.isEmpty, "Mode names outside tr(): \(found)")
    }

    /// Every item of the status menu is in Vietnamese in Vietnamese mode, the mode item included.
    @Test @MainActor func statusMenuHasNoEnglishItemInVietnamese() {
        let titles = Localization.$languageOverride.withValue(true) { MenuBarController().buildMenu().items.map(\.title) }
        let english = ["Show Dashboard", "Auto", "Stop", "Settings…", "Activity Log…", "Why is my Mac awake?…",
                       "Welcome & Safety…", "Check for Updates…", "About CamLid", "Quit CamLid"]
        #expect(english.allSatisfy { !titles.contains($0) }, "English items left: \(titles.filter { english.contains($0) })")
        #expect(titles.contains("Tự động") && titles.contains("Dừng"))
    }

    /// Every catalogue entry keeps its placeholders in the same order in both languages, so a stored message can be carried over.
    @Test func placeholdersKeepTheirOrderInBothLanguages() {
        #expect(Localization.catalogue.count > 600)
        let mismatched = Localization.catalogue.filter { $0.english.specifiers != $0.vietnamese.specifiers }
        #expect(mismatched.isEmpty, "Entries whose placeholders differ: \(mismatched.count)")
    }

    /// Every catalogue entry shows in Vietnamese when its English text is stored, and as the English text otherwise.
    @Test func displayTranslatesEveryCatalogueEntry() {
        var missed: [String] = []
        for entry in Localization.catalogue {
            let arguments = entry.english.specifiers.map { specifier -> String in
                if specifier == "%.1f" { return "3.5" }
                return specifier == "%@" ? "Sample" : "7"
            }
            guard let english = entry.english.filled(arguments), let vietnamese = entry.vietnamese.filled(arguments) else {
                missed.append("unfillable entry"); continue
            }
            let inVietnamese = Localization.$languageOverride.withValue(true) { Localization.display(english) }
            let inEnglish = Localization.$languageOverride.withValue(false) { Localization.display(english) }
            if inVietnamese != vietnamese || inEnglish != english { missed.append(english) }
        }
        #expect(missed.isEmpty, "Entries that do not show in the current language: \(missed.prefix(8))")
    }

    /// The battery notice that stayed in Vietnamese on the Dashboard reads in English after the switch; unknown text is kept.
    @Test func displayShowsAStoredNoticeInTheCurrentLanguage() {
        let stored = "Battery is below the start level. Connect the charger or check the entry level in Safety settings."
        Localization.$languageOverride.withValue(true) {
            #expect(Localization.display(stored) == "Pin thấp hơn mức bắt đầu. Hãy cắm sạc, hoặc kiểm tra mức vào trong cài đặt An toàn.")
            #expect(Localization.display("Helper exited with code 3.") == "Helper exited with code 3.")
        }
        Localization.$languageOverride.withValue(false) {
            #expect(Localization.display(stored) == stored)
        }
    }

    /// The helper's and the Settings editor's status lines are stored in English and shown in the current language.
    @Test @MainActor func statusLinesAreStoredInEnglishAndShownInTheCurrentLanguage() {
        let helper = Localization.$languageOverride.withValue(true) { HelperController(status: { .notInstalled }, keepAwakeApps: { [] }) }
        #expect(helper.message == "Helper status has not been checked.")
        Localization.$languageOverride.withValue(true) {
            #expect(Localization.display(helper.message) == Localization.text("Helper status has not been checked.", vietnamese: true))
        }
        let editor = Localization.$languageOverride.withValue(true) { SettingsEditor(configuration: try! Configuration(), revision: 1) }
        #expect(editor.loginMessage == "Login registration has not been checked.")
        Localization.$languageOverride.withValue(true) {
            #expect(Localization.display(editor.loginMessage) == Localization.text("Login registration has not been checked.", vietnamese: true))
        }
    }
}
