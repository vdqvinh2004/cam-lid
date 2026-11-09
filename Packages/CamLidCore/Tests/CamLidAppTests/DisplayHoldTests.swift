import Foundation
import IOKit.pwr_mgt
import Testing
@testable import CamLidApp

/// Spec 023, User Story 1 (FR-001 to FR-003, SC-001, SC-002): the display option and the choice taken at session start.
@Suite("Display option")
struct DisplayHoldTests {
    /// Records what the power manager is asked to create and release, standing in for IOKit.
    private final class FakePowerManager {
        var created: [String] = []
        var released: [IOPMAssertionID] = []
        private var nextID: IOPMAssertionID = 1

        var system: KeepAwakeSystem {
            KeepAwakeSystem(
                create: { reason in
                    self.created.append(reason)
                    self.nextID += 1
                    return self.nextID
                },
                release: { self.released.append($0) },
                ownAssertionNames: { self.created })
        }
    }

    @Test func theDisplayChoiceIsReadWhileIdleAndHeldDuringASession() {
        var choice = DisplaySleepChoice()
        #expect(!choice.keepsDisplayOn)                                   // by default the display may sleep
        choice.observe(sessionActive: false, displaySleepAllowed: false)
        #expect(choice.keepsDisplayOn)                                    // read while no session runs
        choice.observe(sessionActive: true, displaySleepAllowed: true)    // changed during the session
        #expect(choice.keepsDisplayOn)                                    // waits for the next session
        choice.observe(sessionActive: false, displaySleepAllowed: true)   // the session ended
        #expect(!choice.keepsDisplayOn)
    }

    @Test func byDefaultNoDisplayAssertionIsCreated() {
        let power = FakePowerManager()
        let display = KeepAwakeAssertion(system: power.system, reason: KeepAwakeAssertion.displayReason)
        var choice = DisplaySleepChoice()
        choice.observe(sessionActive: false, displaySleepAllowed: true)
        display.reconcile(wanted: choice.keepsDisplayOn, now: 0)
        #expect(power.created.isEmpty)
        #expect(!display.held)
    }

    @Test func optionOffHoldsExactlyOneDisplayAssertionAndReleasesItAtTheEnd() {
        let power = FakePowerManager()
        let display = KeepAwakeAssertion(system: power.system, reason: KeepAwakeAssertion.displayReason)
        var choice = DisplaySleepChoice()
        choice.observe(sessionActive: false, displaySleepAllowed: false)
        display.reconcile(wanted: choice.keepsDisplayOn, now: 0)
        display.reconcile(wanted: choice.keepsDisplayOn, now: 20)         // re-read; no second assertion
        #expect(power.created == [KeepAwakeAssertion.displayReason])
        #expect(display.verified)
        display.reconcile(wanted: false, now: 40)                         // the session ended
        #expect(power.released.count == 1)
        #expect(!display.held && !display.verified)
    }
}
