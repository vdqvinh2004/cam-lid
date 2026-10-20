import SwiftUI
import CamLidCore

/// The native disclosure label and its trailing space form one keyboard-operable target.
struct RowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption).rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
                .help(configuration.isExpanded ? "Click row to collapse" : "Click row to expand")
            if configuration.isExpanded { configuration.content.padding(.leading, 16) }
        }
    }
}

/// Centralized accessibility contract (specs/005-native-ux T005, FR-018).
///
/// Rules enforced here and referenced by every CamLidApp view:
/// - Every status has a stable `accessibilityIdentifier` (IDs) plus a human
///   label (Labels). The status item posts a value-change notification only
///   for important state transitions; actual VoiceOver behavior needs a native
///   walkthrough. Timers/countdowns never trigger these notifications.
/// - Status is never color-only: every tone ships with text + symbol
///   (StatusTone/StatusStyle). Views pair `dotColor` with `label` always.
/// - Appearance uses semantic colors and the `colorScheme` environment;
///   no hard-coded light/dark palettes. Reduce Motion collapses the
///   120–180 ms MASTER transition to 0. High-contrast mode adds borders
///   where tone would otherwise rely on fill alone.
public enum CamLidAccessibility {
    /// Stable identifiers. Never rename: UI walkthrough and automation key on these.
    public enum IDs {
        public static let statusHeader = "camlid.status.header"
        public static let statusDetail = "camlid.status.detail"
        public static let dashboardMode = "camlid.dashboard.mode"
        public static let dashboardDetails = "camlid.dashboard.details"
        public static let reasonText = "camlid.status.reason"
        public static let leaseRow = "camlid.status.lease"
        public static let healthRows = "camlid.status.health"
        public static let countdownRow = "camlid.status.countdown"
        public static let taskList = "camlid.tasks.list"
        public static let stopButton = "camlid.actions.stop"
        public static let optionsButton = "camlid.actions.options"
        public static let viewLogButton = "camlid.actions.viewLog"
        public static let closeButton = "camlid.actions.close"
        public static let startMenuItem = "camlid.menu.start"
        public static let stopMenuItem = "camlid.menu.stop"
        public static let settingsMenuItem = "camlid.menu.settings"
        public static let quitMenuItem = "camlid.menu.quit"
        public static let settingsTabs = "camlid.settings.tabs"
        public static let settingsApply = "camlid.settings.apply"
        public static let settingsCancel = "camlid.settings.cancel"
        public static let onboardingNext = "camlid.onboarding.next"
        public static let onboardingBack = "camlid.onboarding.back"
        public static let onboardingFinish = "camlid.onboarding.finish"
        public static let closedLidOptInToggle = "camlid.onboarding.closedLidOptIn"
        public static let activitySearch = "camlid.activity.search"
        public static let activityList = "camlid.activity.list"
        public static let activityExport = "camlid.activity.export"
        public static let activityDelete = "camlid.activity.delete"
    }

    /// Human labels. Status labels always include the state word.
    public enum Labels {
        public static func statusLabel(for state: EffectiveState, reason: String?) -> String {
            let base: String
            switch state {
            case .off: base = "Off"
            case .ready: base = "Ready"
            case .protected: base = "Protected"
            case .completionGrace: base = "Waiting after work"
            case .safetyStopped: base = "Stopped by safety"
            case .expired: base = "Session cap reached"
            case .unavailable: base = "Status unavailable"
            case .recoveryRequired: base = "Recovery required"
            }
            guard let reason, !reason.isEmpty else { return "CamLid: \(base)" }
            return "CamLid: \(base), \(reason)"
        }

        public static let stopAction = "Stop protection"
        public static let optionsAction = "Options"
        public static let unknownValue = "Unknown"
    }

    /// Intended order of interactive dashboard controls. Native keyboard
    /// traversal and restoration still require a visible walkthrough.
    public enum FocusOrder {
        public static let dashboard: [String] = [
            IDs.dashboardMode, IDs.stopButton, IDs.viewLogButton,
        ]

        public static func nextIdentifier(after id: String, in order: [String] = dashboard) -> String? {
            guard let index = order.firstIndex(of: id), index + 1 < order.count else { return nil }
            return order[index + 1]
        }
    }

    /// Status tone. Always rendered WITH text and symbol, never alone.
    public enum StatusTone: String, Sendable {
        case ok
        case attention
        case stopped
        case neutral
    }

    /// Text + symbol + tone for one state. Views resolve the actual Color via
    /// `toneColor(_:scheme:contrast:)` so dark/light/high-contrast stay semantic.
    public struct StatusStyle: Sendable, Equatable {
        public let tone: StatusTone
        public let symbolName: String
        public let text: String

        public static func style(for state: EffectiveState) -> StatusStyle {
            switch state {
            case .protected:
                return StatusStyle(tone: .ok, symbolName: "shield.fill", text: "Protected")
            case .ready:
                return StatusStyle(tone: .neutral, symbolName: "shield", text: "Ready")
            case .completionGrace:
                return StatusStyle(tone: .attention, symbolName: "timer", text: "Waiting after work")
            case .safetyStopped, .expired:
                return StatusStyle(tone: .stopped, symbolName: "xmark.shield.fill", text: state == .safetyStopped ? "Stopped — safety" : "Cap reached")
            case .off:
                return StatusStyle(tone: .neutral, symbolName: "shield.slash", text: "Off")
            case .unavailable:
                return StatusStyle(tone: .neutral, symbolName: "questionmark.circle", text: "Unknown")
            case .recoveryRequired:
                return StatusStyle(tone: .stopped, symbolName: "exclamationmark.triangle.fill", text: "Recovery required")
            }
        }
    }

    /// Semantic status color. Uses system colors (auto dark/light adaptation).
    /// Never the sole carrier of state — always paired with StatusStyle text.
    /// Under Increase Contrast, callers additionally draw `contrastOutline`
    /// so tone never relies on fill alone.
    @MainActor
    public static func toneColor(_ tone: StatusTone) -> Color {
        switch tone {
        case .ok: return .green
        case .attention: return .orange
        case .stopped: return .red
        case .neutral: return .secondary
        }
    }

    /// High-contrast outline rule: attention/stopped dots get an outline when
    /// Increase Contrast is on; ok/neutral never need one.
    public static func needsContrastOutline(_ tone: StatusTone, increaseContrast: Bool) -> Bool {
        increaseContrast && (tone == .attention || tone == .stopped)
    }

    /// MASTER allows brief 120–180 ms state transitions, never essential.
    /// Reduce Motion collapses them to zero.
    public static func stateTransitionSeconds(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : 0.15
    }
}
