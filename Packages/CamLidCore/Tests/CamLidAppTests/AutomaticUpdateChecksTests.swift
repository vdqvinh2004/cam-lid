import Foundation
import Testing
@testable import CamLidApp

/// Spec 021 (FR-001, FR-003, SC-001 to SC-003): the once-a-day check. Time and session state are fakes, so no timer runs.
@Suite("Once-a-day update check") @MainActor
struct AutomaticUpdateChecksTests {
    private final class World {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var context = UpdateSafetyContext()
        func advance(hours: Double) { now = now.addingTimeInterval(hours * 3600) }
    }

    /// An in-memory preference store, so a test never reads or writes the app's own settings or a preferences file.
    private func withDefaults(_ body: (MemoryPreferences) throws -> Void) rethrows {
        try body(MemoryPreferences())
    }

    private func controller(_ world: World, _ driver: ProbeStub, _ defaults: any PreferenceStore) -> UpdateController {
        UpdateController(safety: { world.context }, makeDriver: { driver }, defaults: defaults, now: { world.now })
    }

    @Test func offByDefaultAndNeverRequestsOnItsOwn() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            #expect(!updates.automaticChecks && !updates.isScheduled)
            world.advance(hours: 7 * 24)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 0)
        }
    }

    @Test func checksAtMostOnceADayWhileOn() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            updates.setAutomaticChecks(true)
            #expect(updates.isScheduled)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 1)
            driver.finish(.current)
            world.advance(hours: 1)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 1)
            world.advance(hours: 23)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 2)
        }
    }

    @Test func aSessionOrRecoveryWaitsAndTheNextTickTriesAgain() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            updates.setAutomaticChecks(true)
            world.context.sessionActive = true
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 0)
            world.context.sessionActive = false
            world.context.recoveryRequired = true
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 0)
            world.context.recoveryRequired = false
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 1)
        }
    }

    @Test func agentActivityAndUnsavedSettingsDoNotDelayTheDailyCheck() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            updates.setAutomaticChecks(true)
            world.context.agentWorkActive = true
            world.context.unsavedSettings = true
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 1)
        }
    }

    @Test func turningItOffStopsTheChecksAtOnce() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            updates.setAutomaticChecks(true)
            updates.setAutomaticChecks(false)
            #expect(!updates.isScheduled && !updates.automaticChecks)
            world.advance(hours: 3 * 24)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 0)
        }
    }

    @Test func aManualCheckCountsTowardTheDay() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            updates.setAutomaticChecks(true)
            updates.check()
            driver.finish(.current)
            #expect(driver.checks == 1)
            world.advance(hours: 1)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 1)
            world.advance(hours: 23)
            updates.runScheduledCheckIfDue()
            #expect(driver.checks == 2)
        }
    }

    @Test func theDayAndTheSettingSurviveARelaunch() {
        withDefaults { defaults in
            let world = World(), driver = ProbeStub()
            let updates = controller(world, driver, defaults)
            updates.setAutomaticChecks(true)
            updates.runScheduledCheckIfDue()
            driver.finish(.current)
            let nextDriver = ProbeStub()
            let relaunched = controller(world, nextDriver, defaults)
            #expect(relaunched.automaticChecks && relaunched.isScheduled)
            world.advance(hours: 1)
            relaunched.runScheduledCheckIfDue()
            #expect(nextDriver.checks == 0)
            world.advance(hours: 23)
            relaunched.runScheduledCheckIfDue()
            #expect(nextDriver.checks == 1)
        }
    }
}
