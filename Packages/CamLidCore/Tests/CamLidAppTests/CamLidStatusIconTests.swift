import AppKit
import Testing
import CamLidCore
@testable import CamLidApp

/// Every menu-bar mark is a template that adapts to the menu bar's appearance.
struct CamLidStatusIconTests {
    @Test @MainActor func autoStatesHaveDistinctIconsAndTimedUsesText() throws {
        let idle = try #require(CamLidStatusIcon.image(for: .neutral))
        let autoIdle = try #require(CamLidStatusIcon.image(for: .neutral, activeMode: .auto))
        let autoWorking = try #require(CamLidStatusIcon.image(for: .neutral, activeMode: .auto, activityHolding: true))
        let images = try [idle, autoIdle, autoWorking].map { try #require($0.tiffRepresentation) }
        #expect(Set(images).count == 3)
        #expect(CamLidStatusIcon.image(for: .neutral, activeMode: .timed) == nil)
        #expect(CamLidStatusIcon.image(for: .neutral, activeMode: .manual) == nil)
    }
    /// One laptop family, all templates: a white mark vanished on a light menu bar (owner decision 2026-11-01).
    @Test @MainActor func activeSymbolsAreTemplatesThatFollowTheMenuBar() throws {
        for working in [false, true] {
            let image = try #require(CamLidStatusIcon.image(for: .neutral, activeMode: .auto, activityHolding: working))
            #expect(image.isTemplate && image.size == NSSize(width: 18, height: 16))
        }
        #expect(CamLidStatusIcon.image(for: .attention)?.isTemplate == true)
        #expect(DashboardMetric.batterySymbol(percent: 60, onCharger: false) == "battery.50percent")
        #expect(DashboardMetric.batterySymbol(percent: 95, onCharger: false) == "battery.100percent")
        #expect(DashboardMetric.batterySymbol(percent: 5, onCharger: false) == "battery.0percent")
        #expect(DashboardMetric.batterySymbol(percent: 40, onCharger: true) == "powerplug")
    }
    /// The arc turns and the laptop stays: the base has no arc, and the arc is a template the size of the badge.
    @Test @MainActor func spinnerSplitsTheTurningArcFromTheStillLaptop() throws {
        let still = try #require(CamLidStatusIcon.autoSpinnerStill)
        let base = try #require(CamLidStatusIcon.autoSpinnerBase)
        let arc = try #require(CamLidStatusIcon.autoSpinnerArc)
        #expect(still.isTemplate && base.isTemplate && arc.isTemplate)
        #expect(still.size == NSSize(width: 18, height: 16) && base.size == still.size)
        #expect(arc.size == NSSize(width: 9, height: 9))
        let stillPixels = try #require(still.tiffRepresentation)
        let basePixels = try #require(base.tiffRepresentation)
        #expect(stillPixels != basePixels)
        #expect(CamLidStatusIcon.autoSpinnerTurnSeconds == 1.2)
    }
    /// The spinner runs for an Auto session that activity keeps awake: a working agent, or music (owner report 2026-11-11).
    @Test @MainActor func spinnerRunsForAgentWorkAndMusicOnlyInAutoMode() {
        #expect(AppCoordinator.isHoldingForActivity(mode: .auto, agentWorking: true, musicHolding: []))
        #expect(AppCoordinator.isHoldingForActivity(mode: .auto, agentWorking: false, musicHolding: [.browser]))
        #expect(!AppCoordinator.isHoldingForActivity(mode: .auto, agentWorking: false, musicHolding: []))
        #expect(!AppCoordinator.isHoldingForActivity(mode: .timed, agentWorking: true, musicHolding: [.browser]))
        #expect(!AppCoordinator.isHoldingForActivity(mode: nil, agentWorking: true, musicHolding: [.spotify]))
    }
    @Test func menuBarCountdownUsesCompactLiveClockText() {
        #expect(MenuBarCountdown.text(remaining: nil) == nil)
        #expect(MenuBarCountdown.text(remaining: 59.2) == "1:00")
        #expect(MenuBarCountdown.text(remaining: 3_599) == "59:59")
        #expect(MenuBarCountdown.text(remaining: 3_600) == "1:00")
        #expect(MenuBarCountdown.text(remaining: 3_661) == "1:01")
        #expect(MenuBarCountdown.text(remaining: -1) == "0:00")
    }
    @Test @MainActor func infiniteIconUsesTemplateGlyph() throws {
        let image = try #require(CamLidStatusIcon.infinityImage())
        #expect(image.isTemplate)
        #expect(image.size.width > 0 && image.size.height > 0)
    }
    @Test @MainActor func menuBarRendersCountdownAndAgentStates() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu, previousWindowsMenu = app.windowsMenu
        let actions = FakeMenuBarActions()
        let controller = MenuBarController()
        controller.actions = actions
        defer { controller.remove(); app.mainMenu = previousMenu; app.windowsMenu = previousWindowsMenu }
        controller.install()
        let button = try #require(controller.anchorButton)

        actions.mode = .auto
        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, activityHolding: false))
        let idleImage = try #require(button.image)
        #expect(button.title.isEmpty)
        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, activityHolding: true))
        #expect(button.image !== idleImage)
        #expect(button.title.isEmpty)

        actions.mode = .timed
        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, timerRemainingSeconds: 59))
        #expect((button.image?.size.width ?? 0) <= 1)
        #expect(button.title == "0:59")
        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, timerRemainingSeconds: 3_601))
        #expect(button.title == "1:00")
        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, timerRemainingSeconds: nil))
        #expect(button.title.isEmpty)
        #expect(button.image != nil)
        #expect(button.image?.isTemplate == true)
    }
    @Test @MainActor func markRendersForEveryTone() {
        for tone: CamLidAccessibility.StatusTone in [.ok, .attention, .stopped, .neutral] {
            let image = CamLidStatusIcon.image(for: tone)
            #expect(image != nil)
            #expect(image?.size == NSSize(width: 18, height: 16))
            #expect(image?.isTemplate == true)
        }
    }
}

@MainActor
private final class FakeMenuBarActions: MenuBarActions {
    var mode: RequestedMode?
    var menuBarCanStart = true
    var menuBarCanStop = true
    var menuBarAutoAvailable = true
    var menuBarActiveMode: RequestedMode? { mode }
    func menuBarStartProtection() {}
    func menuBarStopProtection() {}
    func menuBarOpenSettings() {}
    func menuBarOpenActivityLog() {}
    func menuBarQuit() {}
}
