import AppKit
import SwiftUI
import Testing
import CamLidCore
@testable import CamLidApp

/// Opt-in visual check (spec 028 T032): renders the five main screens in Vietnamese, light and dark, to PNG files in
/// CAMLID_RENDER_DIR. Runs only with CAMLID_RENDER_LANGUAGE=vi. It changes the shared language, so run it alone:
/// swift test --filter VietnameseRenderTests. It follows DashboardRenderTests and UpdatesRenderTests.
@Suite("Vietnamese render check",
       .enabled(if: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"] != nil
                    && ProcessInfo.processInfo.environment["CAMLID_RENDER_LANGUAGE"] == "vi"))
@MainActor struct VietnameseRenderTests {
    private func write<V: View>(_ view: V, width: CGFloat, named name: String, dark: Bool) throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAMLID_RENDER_DIR"]!, isDirectory: true)
        _ = NSApplication.shared
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

    @Test func theFiveMainScreensInLightAndDark() throws {
        Localization.isVietnamese = true
        defer { Localization.isVietnamese = false }
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "",
                                 capabilityText: "Giữ thức khi đóng nắp đang tắt · helper đã sẵn sàng",
                                 capabilityAction: .enableClosedLid, updateVersion: "0.2.0")
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(DashboardView(data: data, onOpenLog: {}, onClose: {}, onCapabilityAction: { _ in }, onOpenUpdates: {}),
                      width: 380, named: "vi-dashboard-\(suffix).png", dark: dark)
            try write(SettingsView(editor: editor, statusSummary: "Preview", onCommit: { _, revision in .saved(revision: revision + 1) },
                                   onClose: {}, onOpenActivityLog: {}),
                      width: 620, named: "vi-settings-\(suffix).png", dark: dark)
            try write(ActivityLogView(transitions: [], storageError: nil, outcome: nil, isLoading: false, onRefresh: {},
                                      onExportRedacted: {}, onDeleteSession: { _ in }, onDeleteAll: {}, onDeleteResult: { _ in }),
                      width: 640, named: "vi-activity-\(suffix).png", dark: dark)
            try write(OnboardingView(agents: [], isObserving: true, onFinish: { true }, onCancel: {}, onPageChange: { _ in }),
                      width: 520, named: "vi-onboarding-\(suffix).png", dark: dark)
            try write(UpdatesView(snapshot: UpdateSnapshot(phase: .available, reason: "updateAvailable", version: "0.2.0"),
                                  canCheck: true, canInstall: true, installedVersion: "0.1.0", onCheck: {}),
                      width: 460, named: "vi-updates-\(suffix).png", dark: dark)
        }
    }

    /// The Dashboard with readings (normal heat, lid open), a Timed session and an agent whose state is unknown.
    @Test func theDashboardWithReadingsAndATimedSession() throws {
        Localization.isVietnamese = true
        defer { Localization.isVietnamese = false }
        let health = try HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open)
        let agent = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1, observationKnown: false)
        let data = DashboardData(mode: .timed, state: .protected, reasonText: "", capRemainingSeconds: 900, stopEnabled: true,
                                 metrics: DashboardMetric.from(health), agents: [agent])
        for dark in [false, true] {
            try write(DashboardView(data: data, onOpenLog: {}, onClose: {}, onCapabilityAction: { _ in }, onOpenUpdates: {}),
                      width: 380, named: "vi-dashboard-readings-\(dark ? "dark" : "light").png", dark: dark)
            try write(DashboardView(data: data, onOpenLog: {}, onClose: {}, onModeChange: { _ in }, onCapabilityAction: { _ in }, onOpenUpdates: {}),
                      width: 380, named: "vi-dashboard-modes-\(dark ? "dark" : "light").png", dark: dark)
        }
    }

    /// The Auto hint and the Timed duration label in Vietnamese: a dimmed Auto says why, and the Timed row names its duration.
    @Test func theAutoHintAndTheDurationLabelInVietnamese() throws {
        Localization.isVietnamese = true
        defer { Localization.isVietnamese = false }
        let noAgents = DashboardData(mode: .auto, state: .ready, reasonText: "", stopEnabled: false, agents: [])
        let agent = AgentBadgeState(provider: "codex", enabled: true, tasks: [])
        let timed = DashboardData(mode: .timed, state: .protected, reasonText: "", capRemainingSeconds: 3600,
                                  stopEnabled: true, agents: [agent])
        for dark in [false, true] {
            try write(DashboardView(data: noAgents, onOpenLog: {}, onClose: {}, onModeChange: { _ in }, onOpenAgents: {}),
                      width: 380, named: "vi-dashboard-auto-needs-agent-\(dark ? "dark" : "light").png", dark: dark)
            try write(DashboardView(data: timed, onOpenLog: {}, onClose: {}, onModeChange: { _ in },
                                    durationMinutes: 60, onDurationChange: { _ in }, onOpenAgents: {}),
                      width: 380, named: "vi-dashboard-timed-row-\(dark ? "dark" : "light").png", dark: dark)
        }
    }
}
