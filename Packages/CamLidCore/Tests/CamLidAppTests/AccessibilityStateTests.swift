import Testing
import AppKit
import CamLidCore
@testable import CamLidApp

struct AccessibilityStateTests {
    @Test @MainActor func unchangedMenuStatusKeepsItsRenderedImage() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu, previousWindowsMenu = app.windowsMenu
        let controller = MenuBarController()
        defer { controller.remove(); app.mainMenu = previousMenu; app.windowsMenu = previousWindowsMenu }
        controller.install()
        let status = MenuBarStatus(state: .ready)
        controller.update(status: status)
        let button = try #require(controller.anchorButton)
        let image = try #require(button.image)
        controller.update(status: status)
        #expect(button.image === image)
        controller.update(status: MenuBarStatus(state: .off))
        #expect(button.image !== image)
        #expect(button.accessibilityLabel() == "CamLid: Off")
        controller.remove(); controller.install()
        #expect(controller.anchorButton?.accessibilityLabel() == "CamLid: Off")
    }
    @Test func unverifiedProtectionNeverUsesProtectedAccessibilityState() {
        let unverified = MenuBarStatus(state: .protected)
        #expect(unverified.presentedState == .unavailable)
        #expect(unverified.accessibilityLabel == "CamLid: Status unavailable, protection unverified")
        #expect(MenuBarStatus(state: .protected, leaseVerified: true).accessibilityLabel == "CamLid: Protected")
        #expect(CamLidAccessibility.Labels.statusLabel(for: .ready, reason: nil) == "CamLid: Ready")
    }
    @Test func notificationsExcludeRepeatedStateCountdownReasonAndUnverifiedProtection() {
        let previous = MenuBarStatus(state: .completionGrace, reasonText: "10 seconds", leaseVerified: true)
        #expect(!MenuBarStatus(state: .completionGrace, reasonText: "9 seconds", leaseVerified: true).shouldNotifyAccessibility(after: previous))
        #expect(MenuBarStatus(state: .safetyStopped).shouldNotifyAccessibility(after: previous))
        #expect(!MenuBarStatus(state: .protected).shouldNotifyAccessibility(after: MenuBarStatus(state: .unavailable)))
        #expect(!MenuBarStatus(state: .ready).shouldNotifyAccessibility(after: previous))
        #expect(MenuBarStatus(state: .protected, leaseVerified: true).shouldNotifyAccessibility(after: MenuBarStatus(state: .protected)))
    }
}
