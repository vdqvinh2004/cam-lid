import AppKit
import SwiftUI
import Testing
@testable import CamLidApp

/// Opt-in visual check (same pattern as DashboardRenderTests): renders each Updates window state, in light and dark, to PNG
/// files in CAMLID_RENDER_DIR. The window is hosted in a real NSWindow so its AppKit buttons are drawn. Skipped otherwise.
@Suite("Updates render check", .enabled(if: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"] != nil))
@MainActor struct UpdatesRenderTests {
    private func writePNG(_ view: UpdatesView, named name: String, dark: Bool) throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"]!, isDirectory: true)
        _ = NSApplication.shared
        // An opaque background: light text on a transparent PNG disappears in a viewer that shows transparency as white.
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        let height = host.fittingSize.height
        window.setContentSize(NSSize(width: 460, height: height))
        host.frame = NSRect(x: 0, y: 0, width: 460, height: height)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent(name))
    }

    @Test func theUpdatesWindowStatesInLightAndDark() throws {
        let states: [(String, UpdatesView)] = [
            ("available-ready", UpdatesView(snapshot: UpdateSnapshot(phase: .available, reason: "updateAvailable", version: "0.2.0"),
                                            canCheck: true, canInstall: true, installedVersion: "0.1.0", onCheck: {})),
            ("available-session-active", UpdatesView(snapshot: UpdateSnapshot(phase: .available, reason: "updateAvailable", version: "0.2.0"),
                                                     canCheck: true, canInstall: true, sessionActive: true, installedVersion: "0.1.0", onCheck: {})),
            ("available-waiting-settings", UpdatesView(snapshot: UpdateSnapshot(phase: .available, reason: "unsavedSettings", version: "0.2.0"),
                                                       canCheck: true, canInstall: false, installedVersion: "0.1.0", onCheck: {})),
            ("available-no-installer", UpdatesView(snapshot: UpdateSnapshot(phase: .available, reason: "updateAvailable", version: "0.2.0"),
                                                   canCheck: true, canInstall: false, installedVersion: "0.1.0", onCheck: {})),
            ("current", UpdatesView(snapshot: UpdateSnapshot(phase: .current, reason: "latestCompatibleVersion"),
                                    canCheck: true, installedVersion: "0.1.0", onCheck: {})),
            ("ready", UpdatesView(snapshot: UpdateSnapshot(phase: .ready, reason: "manualCheckReady"),
                                  canCheck: true, installedVersion: "0.1.0", onCheck: {})),
            ("unavailable", UpdatesView(snapshot: UpdateSnapshot(phase: .unavailable, reason: "noCompatibleUpdate"),
                                        canCheck: true, installedVersion: "0.1.0", onCheck: {})),
            ("deferred-recovery", UpdatesView(snapshot: UpdateSnapshot(phase: .deferred, reason: "recoveryRequired"),
                                              canCheck: false, installedVersion: "0.1.0", onCheck: {})),
            ("checking", UpdatesView(snapshot: UpdateSnapshot(phase: .checking, reason: "checkingReleases"),
                                     canCheck: false, installedVersion: "0.1.0", onCheck: {})),
            ("error", UpdatesView(snapshot: UpdateSnapshot(phase: .error, reason: "updateCheckFailed"),
                                  canCheck: true, installedVersion: "0.1.0", onCheck: {})),
        ]
        for (name, view) in states {
            try writePNG(view, named: "updates-\(name)-light.png", dark: false)
            try writePNG(view, named: "updates-\(name)-dark.png", dark: true)
        }
    }
}
