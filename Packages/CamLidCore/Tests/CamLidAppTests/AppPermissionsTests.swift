import AppKit
import Foundation
import SwiftUI
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Native app permissions") @MainActor struct AppPermissionsTests {
    @Test func startupCannotRequestRetiredAccessibility() {
        let permissions = AppPermissions(supported: true,
            checkAccessibility: { Issue.record("No AX trust reads"); return false },
            promptAccessibility: { Issue.record("No AX prompts") })
        permissions.requestAtStartup(); permissions.requestAtStartup()
        permissions.refresh(); permissions.requestAccessibility()
        #expect(permissions.accessibility == "notRequired" && !permissions.promptRequested)
    }

    @Test func unsupportedHostNeverOpensSettings() {
        let permissions = AppPermissions(supported: false,
            openSettings: { _ in Issue.record("Unsupported host Settings"); return false })
        permissions.open(.notifications)
        #expect(permissions.settingsError != nil && !permissions.promptRequested)
    }

    @Test func notificationsDestinationAndRetiredRouteRefusal() {
        var urls: [URL] = []
        let permissions = AppPermissions(supported: true, openSettings: { urls.append($0); return false })
        permissions.open(.accessibility)
        #expect(urls.isEmpty && permissions.settingsError != nil)
        permissions.open(.notifications)
        #expect(urls == [AppPermission.notifications.settingsURL, URL(fileURLWithPath: "/System/Applications/System Settings.app")])
        #expect(permissions.settingsError != nil)
        let success = AppPermissions(supported: true, openSettings: { _ in true })
        success.open(.notifications)
        #expect(success.settingsError == nil)
    }

    @Test func oldUtilityAccessibilityIntentCannotPromptOrOpen() throws {
        let permissions = AppPermissions(supported: true,
            checkAccessibility: { Issue.record("No AX reads"); return false },
            promptAccessibility: { Issue.record("No AX prompts") },
            openSettings: { _ in Issue.record("No retired Settings route"); return false })
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(permissions: permissions)
        app.receiveUtilityEvent(.authorizeAccessibility)
        app.receiveUtilityEvent(.visibility(dashboard: false, settings: true))
        app.receiveUtilityEvent(.refreshPermissions)
        app.receiveUtilityEvent(.openPermissionSettings(.accessibility))
        #expect(!permissions.promptRequested && permissions.settingsError != nil)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let status = try #require(object["permissions"] as? [String: Any])
        #expect(status["accessibility"] as? String == "notRequired")
        #expect(object["powerActuation"] as? Bool == false && object["activeSessionMode"] is NSNull)
    }

    @Test func optionalNotificationRequestDoesNotEnableAlertCategories() async throws {
        var status = "notDetermined", prompts = 0
        let notifications = OutcomeNotifications(supported: true, readPermission: { status }, requestPermission: { prompts += 1; status = "authorized" },
            deliver: { _ in Issue.record("Permission is not a notification") })
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(outcomeNotifications: notifications)
        app.receiveUtilityEvent(.authorizeNotifications)
        for _ in 0..<20 { await Task.yield() }
        #expect(prompts == 1 && notifications.permission == "authorized")
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        #expect(object["powerActuation"] as? Bool == false)
    }

    @Test(arguments: ["authorized", "denied", "unavailable", "unknown"]) func notificationsPaneRendersWithoutOSRequests(_ status: String) throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1, section: .general)
        editor.notificationPermission = status
        editor.onAuthorizeNotifications = { Issue.record("Rendering cannot request notifications") }
        let host = NSHostingController(rootView: SettingsView(editor: editor, statusSummary: "No power",
            onCommit: { _, _ in Issue.record("Permissions cannot save config"); return .failed("Fixture") }, onClose: {}, onOpenActivityLog: {}))
        host.view.frame = NSRect(x: 0, y: 0, width: 580, height: 500)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.fittingSize.width > 0 && host.view.fittingSize.height > 0)
        func hasScrollView(_ view: NSView) -> Bool {
            view is NSScrollView || view.subviews.contains { hasScrollView($0) }
        }
        #expect(hasScrollView(host.view))
        #expect(!editor.isDirty && editor.revision == 1)
        let data = try JSONEncoder().encode(UtilityUIEvent.openPermissionSettings(.notifications))
        guard case .openPermissionSettings(.notifications) = try JSONDecoder().decode(UtilityUIEvent.self, from: data) else {
            Issue.record("Notifications route did not round-trip"); return
        }
    }
}
