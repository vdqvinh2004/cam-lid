import AppKit
import SwiftUI
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("Dashboard dismissal ownership", .serialized)
struct DashboardLifecycleTests {
    @Test @MainActor func anchorHitDoesNotDismissWhenEventWindowIsMissingOrDifferent() {
        let outside = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let rect = NSRect(x: 100, y: 100, width: 30, height: 24)
        for window in [nil, outside] {
            #expect(!DashboardDismissal.shouldDismiss(clickWindow: window, popoverWindow: nil, anchorWindow: nil,
                clickScreenPoint: NSPoint(x: 115, y: 112), anchorScreenRect: rect))
        }
        #expect(DashboardDismissal.shouldDismiss(clickWindow: outside, popoverWindow: nil, anchorWindow: nil,
            clickScreenPoint: NSPoint(x: 90, y: 112), anchorScreenRect: rect))
    }
    @Test @MainActor func statusPressOwnsToggleWhileKeyboardAndOutsideDeactivationDismiss() {
        let rect = NSRect(x: 100, y: 100, width: 30, height: 24)
        let inside = NSPoint(x: 115, y: 112)
        // Native status mouse-down deactivates the app before its mouse-up action.
        #expect(!DashboardDismissal.shouldDismissOnDeactivation(mouseButtons: 1,
            mouseScreenPoint: inside, anchorScreenRect: rect))
        #expect(DashboardDismissal.shouldDismissOnDeactivation(mouseButtons: 0,
            mouseScreenPoint: inside, anchorScreenRect: rect))
        #expect(DashboardDismissal.shouldDismissOnDeactivation(mouseButtons: 1,
            mouseScreenPoint: NSPoint(x: 90, y: 112), anchorScreenRect: rect))
        #expect(DashboardDismissal.shouldDismissOnDeactivation(mouseButtons: 1,
            mouseScreenPoint: inside, anchorScreenRect: nil))
        #expect(DashboardDismissal.shouldDismissOnDeactivation(mouseButtons: 2,
            mouseScreenPoint: inside, anchorScreenRect: rect))
    }
    @Test @MainActor func hiddenDashboardNeverInstallsOrReopensMonitors() {
        let popover = NSPopover()
        popover.behavior = .transient
        let lifecycle = DashboardDismissal(popover: popover, anchor: nil)
        #expect(popover.behavior == .applicationDefined)
        for _ in 0..<30 {
            lifecycle.start()
            #expect(!lifecycle.monitoring && !popover.isShown)
            lifecycle.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))
            lifecycle.stop()
            #expect(!lifecycle.monitoring)
        }
    }
    @Test @MainActor func rightAndControlClicksOpenMenuWhileLeftClickTogglesDashboard() {
        #expect(MenuBarController.opensContextMenu(eventType: .rightMouseUp, control: false))
        #expect(MenuBarController.opensContextMenu(eventType: .leftMouseUp, control: true))
        #expect(!MenuBarController.opensContextMenu(eventType: .leftMouseUp, control: false))
        #expect(!MenuBarController.opensContextMenu(eventType: nil, control: false))
    }
    @Test @MainActor func updatingClosedUtilityDoesNotCreateDashboardWindow() throws {
        let app = NSApplication.shared
        let coordinator = UtilityUICoordinator()
        let fixture = QARefinementSupport()
        let state = UtilityUIState(dashboard: fixture.dashboardFixture(), configuration: try Configuration(),
            revision: 1, protection: fixture.protectionFixture(), settingsSection: .agents,
            anchorFrame: .zero, installationPending: false)
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        for _ in 0..<5 { coordinator.update(state) }
        #expect(Set(app.windows.map(ObjectIdentifier.init)) == existingWindows)
    }
    @Test @MainActor func ownedWindowsAndNestedMenusDoNotConsumeInsideClicks() {
        let panel = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let anchor = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let outside = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let menu = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        menu.level = .popUpMenu
        #expect(!DashboardDismissal.shouldDismiss(clickWindow: panel, popoverWindow: panel, anchorWindow: anchor))
        #expect(!DashboardDismissal.shouldDismiss(clickWindow: anchor, popoverWindow: panel, anchorWindow: anchor))
        #expect(!DashboardDismissal.shouldDismiss(clickWindow: menu, popoverWindow: panel, anchorWindow: anchor))
        #expect(DashboardDismissal.shouldDismiss(clickWindow: outside, popoverWindow: panel, anchorWindow: anchor))
        #expect(DashboardDismissal.shouldDismiss(clickWindow: nil, popoverWindow: panel, anchorWindow: anchor))
        #expect(!panel.isVisible && !anchor.isVisible && !outside.isVisible && !menu.isVisible)
    }

    @Test @MainActor func closedSettingsReleasesItsContentHierarchy() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 0)
        weak var retainedHost: NSViewController?
        weak var retainedView: NSView?
        autoreleasepool {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 260),
                styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let content = NSHostingController(rootView: SettingsView(editor: editor, statusSummary: "Preview",
                onCommit: { _, revision in .saved(revision: revision + 1) }, onClose: {}, onOpenActivityLog: {}))
            retainedHost = content
            retainedView = content.view
            window.contentViewController = content
            let guardDelegate = SettingsCloseGuard(editor: editor)
            window.delegate = guardDelegate
            window.close()
            #expect(window.contentViewController == nil)
            #expect(window.contentView == nil)
        }
        #expect(retainedHost == nil)
        #expect(retainedView == nil)
    }

    @Test @MainActor func popoverCloseReleasesContentBeforeNotifyingOwner() {
        let popover = NSPopover()
        var host: NSViewController? = NSViewController()
        popover.contentViewController = host
        var notified = false
        let lifecycle = DashboardDismissal(popover: popover, anchor: nil) {
            #expect(popover.contentViewController == nil)
            host = nil
            notified = true
        }
        lifecycle.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))
        #expect(host == nil && notified)
        #expect(!lifecycle.monitoring)
    }

}
