import AppKit
import SwiftUI
import Testing
@testable import CamLidApp

/// Opt-in visual check (spec 027): renders Dashboard states to PNG files in CAMLID_RENDER_DIR. Skipped otherwise.
@Suite("Dashboard render check", .enabled(if: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"] != nil))
@MainActor struct DashboardRenderTests {
    private func writePNG<V: View>(_ view: V, named name: String) throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"]!, isDirectory: true)
        let renderer = ImageRenderer(content: view.frame(width: 380).background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        let cgImage = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent(name))
    }

    /// Hosted in a real window: ImageRenderer draws AppKit-backed buttons as placeholders, so the Auto button needs this.
    private func writeHostedPNG<V: View>(_ view: V, named name: String, dark: Bool) throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"]!, isDirectory: true)
        _ = NSApplication.shared
        let width: CGFloat = 380
        let host = NSHostingView(rootView: view.frame(width: width).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        let height = host.fittingSize.height
        window.setContentSize(NSSize(width: width, height: height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent(name))
    }

    @Test func theDashboardShowsTheUpdateNoticeAndTheTurnOnFix() throws {
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "",
                                 capabilityText: "Keep awake with the lid closed is off · the helper is ready",
                                 capabilityAction: .enableClosedLid, updateVersion: "0.2.0")
        try writePNG(DashboardView(data: data, onOpenLog: {}, onClose: {}, onCapabilityAction: { _ in }, onOpenUpdates: {}),
                     named: "dashboard-update-and-turn-on.png")
    }

    @Test func theDashboardWithoutAnUpdateShowsNoNotice() throws {
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "")
        try writePNG(DashboardView(data: data, onOpenLog: {}, onClose: {}, onCapabilityAction: { _ in }, onOpenUpdates: {}),
                     named: "dashboard-no-update.png")
    }

    /// The Timed row names its duration beside the picker, as the Auto row names its sleep delay.
    @Test func theTimedRowNamesItsDurationBesideThePicker() throws {
        let agent = AgentBadgeState(provider: "codex", enabled: true, tasks: [])
        let data = DashboardData(mode: .timed, state: .protected, reasonText: "", capRemainingSeconds: 3600,
                                 stopEnabled: true, agents: [agent])
        for dark in [false, true] {
            try writeHostedPNG(DashboardView(data: data, onOpenLog: {}, onClose: {}, onModeChange: { _ in },
                                             durationMinutes: 60, onDurationChange: { _ in }, onOpenAgents: {}),
                               named: "dashboard-timed-row-\(dark ? "dark" : "light").png", dark: dark)
        }
    }

    /// With no agent enabled, Auto is dimmed and the line under the mode buttons says why.
    @Test func theAutoButtonIsDimmedAndSaysWhyWithoutAnAgent() throws {
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "", stopEnabled: false, agents: [])
        for dark in [false, true] {
            try writeHostedPNG(DashboardView(data: data, onOpenLog: {}, onClose: {}, onModeChange: { _ in }, onOpenAgents: {}),
                               named: "dashboard-auto-needs-agent-\(dark ? "dark" : "light").png", dark: dark)
        }
    }
}
