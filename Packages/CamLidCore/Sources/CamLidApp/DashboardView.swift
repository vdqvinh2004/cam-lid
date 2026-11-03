import SwiftUI
import CamLidCore

/// One enrolled task row. `stateText`/`confidenceText` are preformatted by the
/// caller (e.g. "Working · Exact"); the view never invents telemetry.
public struct DashboardTaskRow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: String
    public let stateText: String
    public let confidenceText: String

    public init(id: String, provider: String, stateText: String, confidenceText: String) {
        self.id = id
        self.provider = provider
        self.stateText = stateText
        self.confidenceText = confidenceText
    }
}

/// Read-only glance projection. Policy and CLI retain the original precision.
public struct DashboardMetric: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let symbol: String
    public let value: String
    public let detail: String
    public let attention: Bool

    /// The battery glyph follows the real level (it always showed a full battery); the charger shows a plug.
    static func batterySymbol(percent: Double?, onCharger: Bool) -> String {
        if onCharger { return "powerplug" }
        guard let percent else { return "battery.0percent" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    public static func from(_ health: HealthSnapshot?, isStale: Bool = false) -> [Self] {
        let h = isStale ? nil : health
        let pressure: String = switch h?.thermalPressure {
        case .nominal: "Normal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        default: "Unknown"
        }
        let lid: String = switch h?.lidState {
        case .open: "Open"
        case .closed: "Closed"
        default: "Unknown"
        }
        var rows: [Self] = [
            Self(id: "battery", symbol: Self.batterySymbol(percent: h?.batteryPercent, onCharger: h?.powerSource == .ac),
                value: h?.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "Unknown",
                detail: "Battery: " + (h?.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "Unknown") + ", "
                    + (h?.powerSource == .ac ? "on charger" : h?.powerSource == .battery ? "on battery" : "power source unknown"),
                attention: h?.batteryPercent == nil),
            Self(id: "cpu", symbol: "cpu", value: h?.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "Unknown",
                detail: "CPU: " + (h?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Unknown"), attention: h?.cpuPercent == nil),
            Self(id: "thermal", symbol: "flame", value: pressure,
                detail: "Thermal pressure: " + pressure,
                attention: pressure == "Serious" || pressure == "Critical" || pressure == "Unknown"),
            Self(id: "lid", symbol: "laptopcomputer", value: lid,
                detail: "Lid: " + lid, attention: lid == "Unknown")
        ]
        if let t = h?.temperature, t.availability == "available", let value = t.valueCelsius {
            rows.append(Self(id: "temperature", symbol: "thermometer", value: String(format: "%.1f°C", value),
                detail: (t.displayName ?? "Temperature") + ": " + String(format: "%.1f°C", value), attention: false))
        }
        return rows
    }
}

/// The fix offered beside the closed-lid readiness line when something can be done about it.
public enum CapabilityAction: String, Codable, Sendable, Equatable {
    case installHelper, reinstallHelper, openClosedLidSettings
    public var title: String {
        switch self {
        case .installHelper: "Install Helper…"
        case .reinstallHelper: "Reinstall Helper…"
        case .openClosedLidSettings: "Open Closed Lid Settings…"
        }
    }
    var help: String {
        switch self {
        case .installHelper, .reinstallHelper: "Asks for an administrator password to install the closed-lid helper"
        case .openClosedLidSettings: "Opens Settings › Closed Lid"
        }
    }
}

/// Render model for the compact dashboard panel. All values are injected —
/// countdowns come from explicit deadlines, telemetry strings are nil when
/// unknown (rendered as "Unknown", never green). No live engine wiring.
public struct DashboardData: Codable, Sendable, Equatable {
    public enum Banner: String, Codable, Sendable, Equatable, CaseIterable {
        case grace
        case safety
        case recovery
        case unsupported
    }

    public let mode: RequestedMode
    public let state: EffectiveState
    public let reasonText: String
    /// False (or unverified display sleep) downgrades Protected presentation.
    public let powerActuationAvailable: Bool
    public let leaseVerified: Bool
    public let lidDisplayText: String?
    /// Replaces the fixed preview notice when set (closed-lid readiness on this Mac).
    public let capabilityText: String?
    public let capabilityAction: CapabilityAction?
    public let tasks: [DashboardTaskRow]
    public let taskSummaryText: String
    public let batteryText: String?
    public let thermalText: String?
    public let temperatureText: String?
    public let sensorDetailsText: String?
    public let cpuText: String?
    public let freshnessText: String?
    public let isStale: Bool
    public let graceRemainingSeconds: Double?
    public let capRemainingSeconds: Double?
    public let completionDelayText: String?
    public let banner: Banner?
    public let bannerMessage: String?
    public let lastSessionText: String?
    public let stopEnabled: Bool
    public let startEnabled: Bool
    public let metrics: [DashboardMetric]
    public let agents: [AgentBadgeState]
    public let timerMinutes: Int?
    /// Largest finite duration the active session can accept. On battery this
    /// is the stable safety cap, not the shrinking remaining time.
    public let timerMaximumMinutes: Int?
    public let timerLimitText: String?
    public let sleepDelayMinutes: Int?

    public init(
        mode: RequestedMode = .off,
        state: EffectiveState,
        reasonText: String,
        leaseVerified: Bool = false,
        powerActuationAvailable: Bool = false,
        lidDisplayText: String? = nil,
        capabilityText: String? = nil, capabilityAction: CapabilityAction? = nil,
        tasks: [DashboardTaskRow] = [],
        taskSummaryText: String = "No selected agents reporting work",
        batteryText: String? = nil,
        thermalText: String? = nil,
        temperatureText: String? = nil, sensorDetailsText: String? = nil,
        cpuText: String? = nil,
        freshnessText: String? = nil,
        isStale: Bool = false,
        graceRemainingSeconds: Double? = nil,
        capRemainingSeconds: Double? = nil,
        completionDelayText: String? = nil,
        banner: Banner? = nil,
        bannerMessage: String? = nil,
        lastSessionText: String? = nil,
        stopEnabled: Bool = false, startEnabled: Bool = false, metrics: [DashboardMetric] = DashboardMetric.from(nil), agents: [AgentBadgeState] = [],
        timerMinutes: Int? = nil, timerMaximumMinutes: Int? = nil, timerLimitText: String? = nil,
        sleepDelayMinutes: Int? = nil
    ) {
        self.mode = mode
        self.state = state
        self.reasonText = reasonText
        self.leaseVerified = leaseVerified
        self.powerActuationAvailable = powerActuationAvailable
        self.lidDisplayText = lidDisplayText
        self.capabilityText = capabilityText; self.capabilityAction = capabilityAction
        self.tasks = tasks
        self.taskSummaryText = taskSummaryText
        self.batteryText = batteryText
        self.thermalText = thermalText
        self.temperatureText = temperatureText; self.sensorDetailsText = sensorDetailsText
        self.cpuText = cpuText
        self.freshnessText = freshnessText
        self.isStale = isStale
        self.graceRemainingSeconds = graceRemainingSeconds
        self.capRemainingSeconds = capRemainingSeconds
        self.completionDelayText = completionDelayText
        self.banner = banner
        self.bannerMessage = bannerMessage
        self.lastSessionText = lastSessionText
        self.stopEnabled = stopEnabled
        self.startEnabled = startEnabled; self.metrics = isStale ? DashboardMetric.from(nil) : metrics
        self.agents = agents
        self.timerMinutes = timerMinutes; self.timerMaximumMinutes = timerMaximumMinutes
        self.timerLimitText = timerLimitText; self.sleepDelayMinutes = sleepDelayMinutes
    }

    /// Honest empty state: unknown telemetry, no fabricated values.
    public static func unknown(reason: String) -> DashboardData {
        DashboardData(state: .unavailable, reasonText: reason, isStale: true, stopEnabled: false)
    }
}

/// Formats an explicit remaining-seconds value. MASTER style: "1h 42m" for
/// hours, "1:42" below. Never called with a fabricated duration.
func formatCountdown(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3_600
    let minutes = (total % 3_600) / 60
    let secs = total % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return String(format: "%d:%02d", minutes, secs)
}

/// Compact anchored panel (specs/005-native-ux T002, FR-002/FR-014).
/// Content-driven height with fixed insets; overflow scrolls on small screens.
///
/// Keyboard: native menu navigation exposes options; Esc closes the panel via onExitCommand and the
/// host restores focus to the status item (MenuBarController
/// restoreFocusToStatusItem). VoiceOver: header announces state once;
/// countdown text is NOT announced on change (no live-region spam).
public struct DashboardView: View {
    public let data: DashboardData
    public let onOpenLog: () -> Void
    public let onClose: () -> Void
    public let onModeChange: (@MainActor @Sendable (RequestedMode) -> Void)?
    public let onDurationChange: (@MainActor @Sendable (Int) -> Void)?
    public let durationMinutes: Int
    public let maximumDurationMinutes: Int
    public let sleepDelayMinutes: Int
    public let onSleepDelayChange: (@MainActor @Sendable (Int) -> Void)?
    public let onOpenAgents: (() -> Void)?
    public let onCapabilityAction: ((CapabilityAction) -> Void)?

    public init(data: DashboardData,
        onOpenLog: @escaping () -> Void, onClose: @escaping () -> Void,
        onModeChange: (@MainActor @Sendable (RequestedMode) -> Void)? = nil,
        durationMinutes: Int = 120, onDurationChange: (@MainActor @Sendable (Int) -> Void)? = nil,
        maximumDurationMinutes: Int = 480, sleepDelayMinutes: Int = 2,
        onSleepDelayChange: (@MainActor @Sendable (Int) -> Void)? = nil,
        onOpenAgents: (() -> Void)? = nil, onCapabilityAction: ((CapabilityAction) -> Void)? = nil) {
        self.data = data
        self.onOpenLog = onOpenLog; self.onClose = onClose; self.onModeChange = onModeChange
        self.durationMinutes = durationMinutes; self.onDurationChange = onDurationChange
        self.maximumDurationMinutes = maximumDurationMinutes; self.sleepDelayMinutes = sleepDelayMinutes
        self.onSleepDelayChange = onSleepDelayChange; self.onOpenAgents = onOpenAgents
        self.onCapabilityAction = onCapabilityAction
    }
    public var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }.onExitCommand(perform: onClose)
    }
    private var timerSelection: Int {
        durationMinutes == 0 ? 0 : max(0, min(durationMinutes, maximumDurationMinutes))
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                // While waiting to sleep, the menu bar icon and the countdown below already say so.
                if data.presentedState != .completionGrace {
                    HStack(spacing: 8) {
                        Image(systemName: data.statusSymbol).font(.title3).foregroundStyle(.secondary)
                        // The same word the menu bar reads to VoiceOver ("Stopped" here used to contradict its "Ready").
                        Text(data.statusTitle).font(.headline)
                            .lineLimit(1).truncationMode(.tail)
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.statusHeader)
                        .help(data.statusTitle + (data.displayedReasonText.isEmpty ? "" : ": " + data.displayedReasonText))
                }
                Spacer(minLength: 4)
                Button(action: onOpenLog) { Label("Activity", systemImage: "clock.arrow.circlepath") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Open Activity Log")
                    .accessibilityIdentifier(CamLidAccessibility.IDs.viewLogButton)
            }
            if !data.displayedReasonText.isEmpty {
                Text(data.displayedReasonText).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail).help(data.displayedReasonText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(CamLidAccessibility.IDs.reasonText)
            }
            if !data.powerActuationAvailable {
                PreviewBuildNotice(text: data.capabilityText, font: .caption)
                if let action = data.capabilityAction, let onCapabilityAction {
                    Button(action.title) { onCapabilityAction(action) }
                        .buttonStyle(.link).font(.caption)
                        .help(action.help)
                        .accessibilityIdentifier("camlid.dashboard.capabilityAction")
                }
            }
            HStack {
                if let onModeChange {
                    ModeBadges(selected: data.stopEnabled ? data.mode : .off, onSelect: onModeChange, activatesSession: true,
                        autoEnabled: data.hasEnabledAgents)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.dashboardMode)
                } else { Text("Mode: \(data.mode == .manual ? "Timed" : data.mode.rawValue.capitalized)") }
            }
            if !data.hasEnabledAgents {
                HStack(spacing: 4) {
                    Text("Auto needs an agent.").foregroundStyle(.secondary)
                    if let onOpenAgents {
                        Button("Choose Agents…", action: onOpenAgents)
                            .buttonStyle(.link)
                            .help("Open Settings → Agents to choose which agents may delay sleep")
                            .accessibilityIdentifier("camlid.dashboard.chooseAgents")
                    }
                }
                .font(.caption)
            }
            if let onDurationChange, data.stopEnabled, data.mode == .timed || data.mode == .manual {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Label("Timer", systemImage: "timer").foregroundStyle(.secondary)
                            .help("Timed duration; Infinite runs until stopped or a safety limit, including the battery time limit")
                        Picker("Duration", selection: Binding(get: { timerSelection }, set: onDurationChange)) {
                            Text("∞ Infinite").tag(0)
                            ForEach(NumericChoice.presets(.timer).filter { $0 > 0 && $0 <= maximumDurationMinutes }, id: \.self) { value in
                                Text(NumericChoice.label(value, field: .runCap)).tag(value)
                            }
                            if timerSelection != 0, !NumericChoice.presets(.timer).contains(timerSelection) {
                                Text(NumericChoice.label(timerSelection, field: .runCap)).tag(timerSelection)
                            }
                        }.labelsHidden().accessibilityLabel("Session duration")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help("Changing the duration restarts the timer now; battery exposure keeps its original deadline")
                            .disabled(data.state == .safetyStopped || data.state == .expired)
                            .accessibilityIdentifier("camlid.dashboard.timer")
                    }
                    if let limit = data.timerLimitText {
                        Text(limit).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("camlid.dashboard.timerLimit")
                    }
                }
            }
            if let onSleepDelayChange, data.stopEnabled, data.mode == .auto {
                HStack(spacing: 8) {
                    Label("Sleep when done", systemImage: "moon.zzz").foregroundStyle(.secondary)
                        .help("Auto waits after selected work ends; macOS sleep rules apply")
                    Picker("Sleep when done", selection: Binding(get: { sleepDelayMinutes }, set: onSleepDelayChange)) {
                        ForEach(NumericChoice.presets(.completionDelay), id: \.self) { minutes in
                            Text(minutes == 0 ? "Immediately" : "After \(minutes) min").tag(minutes)
                        }
                        if !NumericChoice.presets(.completionDelay).contains(sleepDelayMinutes) {
                            Text("After \(sleepDelayMinutes) min").tag(sleepDelayMinutes)
                        }
                    }.labelsHidden().accessibilityLabel("Auto sleep delay")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help("Wait this long after selected agents finish, then let the Mac sleep")
                        .disabled(data.state == .safetyStopped || data.state == .expired)
                        .accessibilityIdentifier("camlid.dashboard.sleepDelay")
                }
            }
            if let grace = data.graceRemainingSeconds {
                VStack(spacing: 2) {
                    healthRow(data.graceLabel, formatCountdown(grace))
                }.accessibilityIdentifier("camlid.dashboard.next")
            }
            DashboardMetrics(metrics: data.metrics)
            if data.bannerMessage != nil || !data.listedAgents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !data.listedAgents.isEmpty {
                        BadgeFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(data.listedAgents) { agent in
                                DashboardAgentBadge(agent: agent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.taskList)
                    }
                    // Notices go last so the working agents stay at the top.
                    if let message = data.bannerMessage {
                        CamLidStatusLabel(message, systemImage: "exclamationmark.triangle",
                                          tone: .warning, help: message)
                    }
                }.padding(.top, 4)
            }
        }.padding(10).frame(minWidth: 232, maxWidth: .infinity, alignment: .topLeading)
    }
    private func healthRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
            .font(.caption).accessibilityElement(children: .combine)
    }
}

private struct DashboardMetrics: View {
    let metrics: [DashboardMetric]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(metrics) { metric in metricChip(metric) } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(metrics) { metric in metricChip(metric) }
            }
        }.accessibilityIdentifier(CamLidAccessibility.IDs.healthRows)
    }

    private func metricChip(_ metric: DashboardMetric) -> some View {
        CamLidMetricChip(value: metric.value, systemImage: metric.symbol, detail: metric.detail,
                         attention: metric.attention && metric.value != "Unknown")
    }
}


public extension DashboardData {
    var timerRemainingSeconds: Double? {
        mode == .timed || mode == .manual ? capRemainingSeconds : nil
    }
    /// Running rows: currently working AND enabled in Settings.
    var workingAgents: [AgentBadgeState] {
        agents.filter { $0.detectionEnabled && $0.workingCount > 0 }.sortedForAgentDisplay()
    }
    /// Waiting rows: enabled, waiting for the user, and not also working.
    /// Shown distinctly; waiting never holds power.
    var waitingAgents: [AgentBadgeState] {
        agents.filter { $0.detectionEnabled && $0.workingCount == 0 && $0.waitingCount > 0 }.sortedForAgentDisplay()
    }
    /// The dashboard shows one scan-friendly A–Z list across both states.
    var listedAgents: [AgentBadgeState] {
        (workingAgents + waitingAgents).sortedForAgentDisplay()
    }
    /// Whether the user selected any agent for detection. The empty-state hint shows
    /// only in this case; enabled-but-idle shows no agent section at all.
    var hasEnabledAgents: Bool {
        agents.contains { $0.detectionEnabled }
    }

    var displayedReasonText: String {
        reasonText == AppCoordinator.noSessionReason ? "" : reasonText
    }
    var presentedState: EffectiveState {
        state == .protected && (!leaseVerified || !powerActuationAvailable) ? .unavailable : state
    }
    var statusTitle: String {
        if presentedState == .completionGrace && !powerActuationAvailable { return "Waiting after work" }
        return CamLidAccessibility.StatusStyle.style(for: presentedState).text
    }
    var statusSymbol: String { CamLidAccessibility.StatusStyle.style(for: presentedState).symbolName }
    var graceLabel: String { powerActuationAvailable ? "Sleep requested in" : "Delay remaining" }
}

extension NSHostingController where Content == DashboardView {
    /// Measure this exact view at its display width, including optional rows and wrapped hints.
    func dashboardContentSize(width: CGFloat, maximumHeight: CGFloat) -> NSSize {
        let measured = sizeThatFits(in: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return NSSize(width: width, height: min(ceil(measured.height), maximumHeight))
    }
}

#Preview("Unknown telemetry") {
    DashboardView(data: .unknown(reason: "Readings unavailable"), onOpenLog: {}, onClose: {})
        .frame(width: 390, height: 300)
}

#Preview("Sleep when done") {
    DashboardView(data: DashboardData(mode: .auto, state: .completionGrace,
        reasonText: "Preview session", graceRemainingSeconds: 90, stopEnabled: true),
        onOpenLog: {}, onClose: {})
        .frame(width: 390, height: 360)
}
