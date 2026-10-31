import AppKit
import SwiftUI
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("Stable utility layouts", .serialized)
@MainActor struct StableLayoutTests {
    @Test func dashboardHeightTracksActualContentAcrossModesAndHints() throws {
        let idle = AgentBadgeState(provider: "orca", enabled: true, tasks: [])
        let task = try AgentTask(id: "orca/work", sessionID: "s", runID: "r",
            state: .working, evidenceKind: .lifecycle, confidence: .exact)
        let working = AgentBadgeState(provider: "orca", enabled: true, tasks: [task])
        for mode in [RequestedMode.off, .auto, .timed] {
            for agents in [[AgentBadgeState](), [idle], [working]] {
                for reason in ["", "No selected agents reporting work"] {
                    let data = DashboardData(mode: mode, state: .ready, reasonText: reason,
                        capRemainingSeconds: mode == .timed ? 900 : nil,
                        stopEnabled: mode != .off, agents: agents)
                    let host = NSHostingController(rootView: DashboardView(data: data,
                        onOpenLog: {}, onClose: {}, onModeChange: { _ in },
                        onDurationChange: { _ in }, onSleepDelayChange: { _ in }, onOpenAgents: {}))
                    host.sizingOptions = []
                    let actual = host.sizeThatFits(in: NSSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
                    let displayed = host.dashboardContentSize(width: 390, maximumHeight: 1000)
                    #expect(displayed.width == 390)
                    #expect(abs(displayed.height - actual.height) <= 1,
                        "Mode \(mode), agents \(agents.count), reason \(reason): \(displayed.height) vs \(actual.height)")
                    #expect(host.dashboardContentSize(width: 390, maximumHeight: 140).height <= 140)
                    host.rootView = DashboardView(data: DashboardData(mode: .off, state: .off, reasonText: ""),
                        onOpenLog: {}, onClose: {})
                    let updated = host.sizeThatFits(in: NSSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
                    #expect(abs(host.dashboardContentSize(width: 390, maximumHeight: 1000).height - updated.height) <= 1)
                }
            }
        }
    }

    @Test func dashboardAgentBadgesWrapToNextLine() throws {
        let agents = try AgentBadgeState.providers.map { provider in
            let task = try AgentTask(id: "\(provider)/work", sessionID: "s", runID: "r",
                state: .working, evidenceKind: .lifecycle, confidence: .exact)
            return AgentBadgeState(provider: provider, enabled: true, tasks: [task])
        }
        let data = DashboardData(mode: .auto, state: .ready, reasonText: "",
            stopEnabled: true, agents: agents)
        let host = NSHostingController(rootView: DashboardView(data: data,
            onOpenLog: {}, onClose: {}, onModeChange: { _ in },
            onDurationChange: { _ in }, onSleepDelayChange: { _ in }, onOpenAgents: {}))
        host.sizingOptions = []
        let wide = host.sizeThatFits(in: NSSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        let narrow = host.sizeThatFits(in: NSSize(width: 240, height: CGFloat.greatestFiniteMagnitude))
        #expect(narrow.height > wide.height + 20,
            "Badges should flow onto additional lines at a narrow dashboard width")
    }

    /// HIG: a settings window fits the selected pane; it keeps its top edge and width (owner-approved 2026-11-01).
    @Test func settingsTabsKeepWindowFrame() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 580, height: 540),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let toolbar = SettingsToolbar(editor: editor, window: window)
        let initial = window.frame
        for section in SettingsSection.allCases {
            editor.section = section
            toolbar.select(section)
            #expect(window.frame.maxY == initial.maxY && window.frame.width == initial.width, "Tab \(section) moved Settings")
            #expect(abs(window.contentRect(forFrameRect: window.frame).height - section.preferredHeight) <= 1)
            #expect(window.title == section.title)
        }
        window.close()
    }
}
