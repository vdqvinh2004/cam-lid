import Foundation
import Testing
@testable import CamLidCore

@Suite struct PowerModeTests {
    @Test func standardIsTheDefaultOrderAndStrictIsExperimental() {
        #expect(PowerMode.allCases.first == .standard)
        #expect(!PowerMode.standard.isExperimental && PowerMode.strict.isExperimental)
        #expect(PowerMode.strict.disclosure.hasPrefix("Experimental"))
        #expect(PowerMode.standard.disclosure.contains("global sleep setting"))
    }

    @Test func switchingIsRefusedWhileEitherModeIsBusyOrTheTargetIsUnavailable() {
        func decide(lease: Bool = false, journal: Bool = false, available: Bool = true) -> PowerModeSwitchDecision {
            PowerModeSwitch.decide(from: .standard, to: .strict, leaseActive: lease, journalUnresolved: journal, targetAvailable: available)
        }
        #expect(decide() == .allowed)
        #expect(decide(lease: true) == .refused(reason: "leaseActive"))
        #expect(decide(journal: true) == .refused(reason: "journalUnresolved"))
        #expect(decide(available: false) == .refused(reason: "modeUnavailable"))
        #expect(PowerModeSwitch.decide(from: .strict, to: .strict, leaseActive: true, journalUnresolved: true, targetAvailable: false) == .allowed)
    }

    @Test func olderPreferencesMeanStandardAndThePatchRejectsUnknownModes() throws {
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration())) as! [String: Any]
        dictionary.removeValue(forKey: "powerMode")
        let old = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: dictionary))
        #expect(old.powerMode == .standard)
        #expect(try ConfigPatch(jsonDictionary: ["powerMode": "strict"]).powerMode == .strict)
        #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: ["powerMode": "everything"]) }
        #expect(try Configuration().applying(ConfigPatch(jsonDictionary: ["powerMode": "strict"])).powerMode == .strict)
    }
}
