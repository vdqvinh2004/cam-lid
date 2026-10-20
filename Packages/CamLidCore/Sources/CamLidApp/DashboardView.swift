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
            Self(id: "battery", symbol: h?.powerSource == .ac ? "powerplug" : "battery.100percent",
                value: h?.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "Unknown",
                detail: "Battery: " + (h?.batteryPercent.map { String(format: "%.1f%%", $0) } ?? "Unknown") + ", power: " + (h?.powerSource.rawValue ?? "unknown"), attention: h?.batteryPercent == nil),
            Self(id: "cpu", symbol: "cpu", value: h?.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "Unknown",
                detail: "CPU: " + (h?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Unknown"), attention: h?.cpuPercent == nil),
            Self(id: "thermal", symbol: "flame", value: pressure,
                detail: "Thermal pressure: " + pressure + ". This is not temperature in degrees.",
                attention: pressure == "Serious" || pressure == "Critical" || pressure == "Unknown"),
            Self(id: "lid", symbol: "laptopcomputer", value: lid,
                detail: "Lid: " + lid + ". Display sleep and system continuity are separate observations.", attention: lid == "Unknown")
        ]
        if let t = h?.temperature, t.availability == "available", let value = t.valueCelsius {
            rows.append(Self(id: "temperature", symbol: "thermometer", value: String(format: "%.1f°C", value),
                detail: (t.displayName ?? "Temperature") + ": " + String(format: "%.2f°C", value) + ", source: " + (t.source ?? "Unknown"), attention: false))
        }
        return rows
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
    public let sleepDelayMinutes: Int?

    public init(
        mode: RequestedMode = .off,
        state: EffectiveState,
        reasonText: String,
        leaseVerified: Bool = false,
        powerActuationAvailable: Bool = false,
        lidDisplayText: String? = nil,
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
        timerMinutes: Int? = nil, sleepDelayMinutes: Int? = nil
    ) {
        self.mode = mode
        self.state = state
        self.reasonText = reasonText
        self.leaseVerified = leaseVerified
        self.powerActuationAvailable = powerActuationAvailable
        self.lidDisplayText = lidDisplayText
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
        self.timerMinutes = timerMinutes; self.sleepDelayMinutes = sleepDelayMinutes
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

    public init(data: DashboardData,
        onOpenLog: @escaping () -> Void, onClose: @escaping () -> Void,
        onModeChange: (@MainActor @Sendable (RequestedMode) -> Void)? = nil,
        durationMinutes: Int = 120, onDurationChange: (@MainActor @Sendable (Int) -> Void)? = nil,
        maximumDurationMinutes: Int = 480, sleepDelayMinutes: Int = 2,
        onSleepDelayChange: (@MainActor @Sendable (Int) -> Void)? = nil,
        onOpenAgents: (() -> Void)? = nil) {
        self.data = data
        self.onOpenLog = onOpenLog; self.onClose = onClose; self.onModeChange = onModeChange
        self.durationMinutes = durationMinutes; self.onDurationChange = onDurationChange
        self.maximumDurationMinutes = maximumDurationMinutes; self.sleepDelayMinutes = sleepDelayMinutes
        self.onSleepDelayChange = onSleepDelayChange; self.onOpenAgents = onOpenAgents
    }
    public var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }.onExitCommand(perform: onClose)
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: data.statusSymbol).font(.title3).foregroundStyle(.secondary)
                    Text(data.presentedState == .off || (!data.stopEnabled && data.presentedState == .ready) ? "Stopped" : data.statusTitle).font(.headline)
                        .lineLimit(1).truncationMode(.tail)
                }.accessibilityElement(children: .combine)
                    .accessibilityIdentifier(CamLidAccessibility.IDs.statusHeader)
                    .help(data.statusTitle + (data.displayedReasonText.isEmpty ? "" : ": " + data.displayedReasonText))
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
                Label("Preview · power control unavailable", systemImage: "shield.slash")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Sessions preview CamLid behavior. This build does not keep the Mac awake or change lid-close sleep.")
            }
            HStack {
                if let onModeChange {
                    ModeBadges(selected: data.stopEnabled ? data.mode : .off, onSelect: onModeChange, activatesSession: true,
                        autoEnabled: data.hasEnabledAgents)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.dashboardMode)
                } else { Text("Mode: \(data.mode == .manual ? "Timed" : data.mode.rawValue.capitalized)") }
            }
            if let onDurationChange, data.stopEnabled, data.mode == .timed || data.mode == .manual {
                HStack(spacing: 8) {
                    Label("Timer", systemImage: "timer").foregroundStyle(.secondary)
                        .help("Timed duration; Infinite runs until stopped or a safety limit, including the battery time limit")
                    Picker("Duration", selection: Binding(get: { durationMinutes }, set: onDurationChange)) {
                        Text("∞ Infinite").tag(0)
                        ForEach(NumericChoice.presets(.timer).filter { $0 > 0 && $0 <= maximumDurationMinutes }, id: \.self) { value in
                            Text(NumericChoice.label(value, field: .runCap)).tag(value)
                        }
                        if durationMinutes != 0, !NumericChoice.presets(.timer).filter({ $0 <= maximumDurationMinutes }).contains(durationMinutes) {
                            Text(NumericChoice.label(durationMinutes, field: .runCap)).tag(durationMinutes)
                        }
                    }.labelsHidden().accessibilityLabel("Session duration")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help("Changing the duration restarts the timer now; battery exposure keeps its original deadline")
                        .disabled(data.state == .safetyStopped || data.state == .expired)
                        .accessibilityIdentifier("camlid.dashboard.timer")
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
                        .help("Wait after selected agents finish; this preview does not actuate sleep")
                        .disabled(data.state == .safetyStopped || data.state == .expired)
                        .accessibilityIdentifier("camlid.dashboard.sleepDelay")
                }
            }
            if data.graceRemainingSeconds != nil || data.timerRemainingSeconds != nil {
                VStack(spacing: 2) {
                    if let grace = data.graceRemainingSeconds { healthRow(data.graceLabel, formatCountdown(grace)) }
                    if let cap = data.timerRemainingSeconds { healthRow("Timer remaining", formatCountdown(cap)) }
                }.accessibilityIdentifier("camlid.dashboard.next")
            }
            DashboardMetrics(metrics: data.metrics)
            if data.bannerMessage != nil || !data.hasEnabledAgents || !data.workingAgents.isEmpty || !data.waitingAgents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = data.bannerMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).fixedSize(horizontal: false, vertical: true).help(message)
                    }
                    if !data.hasEnabledAgents {
                        Text(data.taskSummaryText).font(.callout).foregroundStyle(.secondary)
                        if let onOpenAgents {
                            Button("Choose agents…", action: onOpenAgents)
                                .buttonStyle(.link).font(.callout)
                                .help("Open Settings → Agents to choose which agents may delay sleep")
                                .accessibilityIdentifier("camlid.dashboard.chooseAgents")
                        }
                    }
                    if !data.workingAgents.isEmpty || !data.waitingAgents.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                        ForEach(data.workingAgents + data.waitingAgents) { agent in
                            HStack(alignment: .center, spacing: 6) {
                                AgentMarkView(provider: agent.provider).help(agent.title)
                                Text(agent.title).font(.callout).bold().lineLimit(1)
                                Spacer(minLength: 4)
                                if agent.waitingCount > 0 {
                                    Label("\(agent.waitingCount)", systemImage: "hourglass")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .accessibilityLabel(agent.waitingCount == 1 ? "1 task waiting for user" : "\(agent.waitingCount) tasks waiting for user")
                                        .help("Tasks waiting for user input in " + agent.title + ". Waiting never holds power.")
                                }
                                if agent.workingCount > 0 {
                                    Label("\(agent.workingCount)", systemImage: "terminal")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .accessibilityLabel(agent.workingCount == 1 ? "1 reported working task" : "\(agent.workingCount) reported working tasks")
                                        .help("Working tasks reported by " + agent.title)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 6)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                .help(agent.detail + (agent.workingCount > 0 ? " · May delay sleep. " : " · Waiting never holds power. ") + agent.observationExplanation)
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(agent.observationExplanation)
                                .accessibilityIdentifier("camlid.observed." + agent.provider)
                        }
                        }.accessibilityIdentifier(CamLidAccessibility.IDs.taskList)
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
            HStack(spacing: 6) { ForEach(metrics) { DashboardMetricBadge(metric: $0) } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(metrics) { DashboardMetricBadge(metric: $0) }
            }
        }.accessibilityIdentifier(CamLidAccessibility.IDs.healthRows)
    }
}

private struct DashboardMetricBadge: View {
    let metric: DashboardMetric
    var body: some View {
        Label(metric.value, systemImage: metric.symbol)
            .font(.caption).monospacedDigit()
            .foregroundStyle(metric.attention && metric.value != "Unknown" ? Color.orange : Color.primary)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .help(metric.detail).accessibilityLabel(metric.detail)
    }
}


public extension DashboardData {
    var timerRemainingSeconds: Double? {
        mode == .timed || mode == .manual ? capRemainingSeconds : nil
    }
    /// Running rows: currently working AND enabled in Settings.
    var workingAgents: [AgentBadgeState] {
        agents.filter { $0.detectionEnabled && $0.workingCount > 0 }
    }
    /// Waiting rows: enabled, waiting for the user, and not also working.
    /// Shown distinctly; waiting never holds power.
    var waitingAgents: [AgentBadgeState] {
        agents.filter { $0.detectionEnabled && $0.workingCount == 0 && $0.waitingCount > 0 }
    }
    /// Whether the user selected any agent for detection. The empty-state hint shows
    /// only in this case; enabled-but-idle shows no agent section at all.
    var hasEnabledAgents: Bool {
        agents.contains { $0.detectionEnabled }
    }

    var displayedReasonText: String {
        ["Ready to start a preview", "preview — no power actuation"].contains(reasonText) ? "" : reasonText
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
