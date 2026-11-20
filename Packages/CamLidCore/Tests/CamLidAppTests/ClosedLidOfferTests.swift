import Testing
@testable import CamLidApp

@Suite("Closed-lid offer (spec 027)")
struct ClosedLidOfferTests {
    @Test func theHelperStateDecidesTheNextStep() {
        #expect(ClosedLidOffer.offer(helperState: "installed", optionOn: false, macAllowed: true) == .turnOn)
        #expect(ClosedLidOffer.offer(helperState: "installed", optionOn: true, macAllowed: true) == .none)
        #expect(ClosedLidOffer.offer(helperState: "notInstalled", optionOn: false, macAllowed: true) == .installHelper)
        #expect(ClosedLidOffer.offer(helperState: "notInstalled", optionOn: true, macAllowed: true) == .installHelper)
        for state in ["needsReauthorization", "needsHelperUpdate", "installedNotLoaded"] {
            #expect(ClosedLidOffer.offer(helperState: state, optionOn: false, macAllowed: true) == .reinstallHelper, "\(state)")
        }
        #expect(ClosedLidOffer.offer(helperState: "partial", optionOn: false, macAllowed: true) == .openSettings)
        #expect(ClosedLidOffer.offer(helperState: "unknown", optionOn: false, macAllowed: true) == .openSettings)
    }

    @Test func aMacThatCannotUseClosedLidAlwaysSendsTheUserToSettings() {
        for state in ["installed", "notInstalled", "needsReauthorization"] {
            for on in [false, true] {
                #expect(ClosedLidOffer.offer(helperState: state, optionOn: on, macAllowed: false) == .openSettings)
            }
        }
    }

    @Test func theOptionIsLockedOnlyWhileItIsOffAndTheHelperIsNotReady() {
        #expect(!ClosedLidOffer.optionEnabled(helperState: "notInstalled", optionOn: false))
        #expect(!ClosedLidOffer.optionEnabled(helperState: "needsHelperUpdate", optionOn: false))
        #expect(ClosedLidOffer.optionEnabled(helperState: "installed", optionOn: false))
        // An option that is already on stays switchable off, even when the helper is gone.
        #expect(ClosedLidOffer.optionEnabled(helperState: "notInstalled", optionOn: true))
    }
}
