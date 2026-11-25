import SwiftUI
import AppKit
import CamLidCore

/// Provider mark: official artwork fitted into one fixed square. Raster marks
/// scale to fit, the OpenCode vector is scaled from its 24×24 design box, and
/// unknown providers use a matching glyph fallback.
struct AgentMarkView: View {
    static let defaultSize: CGFloat = 28
    let provider: String
    var size: CGFloat = Self.defaultSize
    static func image(for provider: String) -> NSImage? {
        guard let name = AgentProviderCatalog.info(for: provider)?.assetName,
              let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.accessibilityDescription = provider
        return image
    }
    /// Marks that are a bare glyph rather than a tile; they sit centred on a neutral tile.
    static let glyphMarks: Set<String> = ["opencode", "antigravity", "cline", "vscode-copilot", "copilot-cli", "goose"]
    /// App-icon artwork that ships with its own transparent margin, enlarged so it fills the tile like the others.
    static let marginScale: [String: CGFloat] = ["orca": 1.08, "codex": 1.05]

    /// Every agent gets the same rounded tile at the same size: tile-shaped artwork is clipped to it, glyphs are
    /// centred at about 72% on a neutral tile (four different shapes made marks look unevenly sized).
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        let glyph = Self.glyphMarks.contains(provider) || Self.image(for: provider) == nil
        artwork
            .scaleEffect(glyph ? 0.72 : Self.marginScale[provider] ?? 1)
            .frame(width: size, height: size)
            .background(glyph ? AnyShapeStyle(Color.primary.opacity(0.1)) : AnyShapeStyle(Color.clear), in: tile)
            .clipShape(tile)
            .overlay(tile.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if provider == "opencode" {
                OpenCodeMark()
            } else if let image = Self.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(provider == "cline" ? .template : .original)
                    .resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(.primary)
            } else if let symbol = AgentProviderCatalog.info(for: provider)?.symbolName {
                Image(systemName: symbol).resizable().scaledToFit()
                    .foregroundStyle(.secondary)
            } else if let monogram = AgentProviderCatalog.info(for: provider)?.monogram {
                Text(monogram)
                    .font(.system(size: size * 0.78, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: "person.crop.circle").resizable().scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// OpenCode terminal frame, redrawn from CC0 path data in its native 24×24
/// coordinate space, then scaled uniformly into the shared square frame.
private struct OpenCodeMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 24, size.height / 24)
            let offset = CGPoint(x: (size.width - 24 * scale) / 2,
                                 y: (size.height - 24 * scale) / 2)
            context.translateBy(x: offset.x, y: offset.y)
            context.scaleBy(x: scale, y: scale)
            var path = Path()
            path.addRect(CGRect(x: 2, y: 0, width: 20, height: 24))
            path.addRect(CGRect(x: 7, y: 4.8, width: 10, height: 14.4))
            context.fill(path, with: .color(.primary), style: FillStyle(eoFill: true))
        }
    }
}

public struct AgentBadgeState: Codable, Equatable, Identifiable, Sendable {
    public static let providers = AgentProviderCatalog.ids
    public var id: String { provider }
    public let provider: String
    public let detectionEnabled: Bool
    public let readiness: String
    public let observedState: String
    public let workingCount: Int
    public let waitingCount: Int
    public let evidenceAgeSeconds: Double?
    public let confidence: String
    public let unknownCount: Int
    public let processCount: Int?
    public let cliDetected: Bool?
    public let appDetected: Bool?
    /// Working/idle comes only from outside activity inference (spec 015), so it is an estimate.
    public let estimated: Bool
    public init(provider: String, enabled: Bool, tasks: [AgentTask], evidenceAgeSeconds: Double? = nil, processCount: Int = 0, cliDetected: Bool? = nil, appDetected: Bool = false, observationKnown: Bool = true) {
        self.provider = provider; detectionEnabled = enabled
        self.evidenceAgeSeconds = evidenceAgeSeconds
        self.processCount = min(20, max(0, processCount))
        self.cliDetected = cliDetected
        self.appDetected = appDetected
        // Caller scopes rows using the normalized provider tuple.
        let rows = tasks
        estimated = rows.contains { $0.evidenceKind == .activity } && !rows.contains { $0.evidenceKind == .lifecycle }
        workingCount = rows.filter { $0.state == .working }.count
        waitingCount = rows.filter { $0.state == .waiting }.count
        unknownCount = rows.filter { $0.state == .unknown }.count
        confidence = rows.isEmpty || rows.contains(where: { $0.confidence == .unknown }) ? "unknown" : rows.contains(where: { $0.confidence == .inferred }) ? "inferred" : "exact"
        readiness = rows.isEmpty ? "disconnected" : "connected"
        // Orca's receipts come once per poll, so its evidence stays fresh for the whole stale window, not for one poll.
        let unknownAfter = provider == OrcaHostResolver.providerID ? OrcaHostResolver.staleSeconds : 15
        observedState = rows.isEmpty ? ((!observationKnown || processCount > 0) ? "Unknown" : "Not detected")
            : workingCount > 0 ? "Active" : unknownCount > 0 ? "Unknown"
            : waitingCount > 0 ? "Waiting" : (evidenceAgeSeconds.map { $0 > unknownAfter } == true ? "Unknown" : "Inactive")
    }
    private enum CodingKeys: String, CodingKey {
        case provider, detectionEnabled, readiness, observedState, workingCount, waitingCount, unknownCount, evidenceAgeSeconds, confidence, processCount, cliDetected, appDetected, estimated
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider); try c.encode(detectionEnabled, forKey: .detectionEnabled)
        try c.encode(readiness, forKey: .readiness); try c.encode(observedState, forKey: .observedState)
        try c.encode(workingCount, forKey: .workingCount); try c.encode(waitingCount, forKey: .waitingCount)
        try c.encode(unknownCount, forKey: .unknownCount); try c.encode(evidenceAgeSeconds, forKey: .evidenceAgeSeconds)
        try c.encode(confidence, forKey: .confidence); try c.encode(processCount ?? 0, forKey: .processCount)
        try c.encodeIfPresent(cliDetected, forKey: .cliDetected)
        try c.encodeIfPresent(appDetected, forKey: .appDetected)
        try c.encode(estimated, forKey: .estimated)
    }
    var title: String { AgentProviderCatalog.title(for: provider) }
    var supportsDetection: Bool {
        AgentProviderCatalog.info(for: provider)?.supportsDetection == true
    }
    var isDetected: Bool {
        (processCount ?? 0) > 0 || readiness == "connected"
            || cliDetected == true || appDetected == true
    }
    /// Settings disables unsupported or undetected agents. A supported but
    /// not-yet-detected agent says so; an unimplemented detector says "Soon".
    var settingsUnavailableReason: String? {
        if !supportsDetection { return tr("Support soon") }
        if !isDetected { return tr("Not detected") }
        return nil
    }
    var installationText: String {
        if cliDetected == true { return tr("CLI detected") }
        if appDetected == true { return tr("App detected") }
        if cliDetected == false { return tr("Not detected") }
        return tr("Checking…")
    }
    /// Bundled raster mark, if this provider ships one. OpenCode renders as a vector
    /// below; unknown providers get the generic glyph.
    var markAssetName: String? { AgentProviderCatalog.info(for: provider)?.assetName }
    /// Providers whose mark is drawn in code rather than bundled raster art.
    var usesVectorMark: Bool { provider == "opencode" }
    var detail: String { readiness == "disconnected" && (processCount ?? 0) > 0 ? tr("Process found · no task reported") : workingCount > 0 ? compactDetail + (unknownCount > 0 ? trf(" · %lld unknown", unknownCount) : "") : waitingCount > 0 ? compactDetail : tr(observedState) }
    var observationExplanation: String {
        let receipt: String
        if let age = evidenceAgeSeconds, age.isFinite, age >= 0 {
            receipt = age >= 3_600 ? tr("Last update over an hour ago.")
                : trf("Last update %@ seconds ago.", age.formatted(.number.precision(.fractionLength(0)).locale(Localization.locale)))
        } else {
            receipt = tr("No update yet.")
        }
        let qualification = provider == "orca"
            ? tr("Orca reports the state of its own panes only.")
            : tr("Estimated from the agent's activity; a running process alone proves nothing.")
        return trf("Confidence: %@. %@ %@ Tasks waiting for you never keep the Mac awake.", tr(confidence), receipt, qualification)
    }
    static func workingSummary(_ agents: [Self]) -> String {
        let count = agents.filter { $0.detectionEnabled && $0.workingCount > 0 }.count
        return count == 0 ? tr("No selected agents reporting work")
            : count == 1 ? tr("1 selected agent reporting work") : trf("%lld selected agents reporting work", count)
    }
    static func waitingSummary(_ agents: [Self]) -> String {
        let count = agents.filter { $0.detectionEnabled && $0.workingCount == 0 && $0.waitingCount > 0 }.count
        return count == 0 ? tr("No selected agents waiting for user")
            : count == 1 ? tr("1 selected agent waiting for user") : trf("%lld selected agents waiting for user", count)
    }
    var compactDetail: String {
        let text = baseCompactDetail
        return estimated && readiness == "connected" ? text + tr(" (estimated)") : text
    }

    private var baseCompactDetail: String {
        if readiness == "disconnected" { return observedState == "Unknown" ? tr("No task reported") : tr("Not detected") }
        if workingCount > 0 { return trf("Active · %lld %@", workingCount, workingCount == 1 ? tr("task") : tr("tasks")) + (waitingCount > 0 ? trf(" · %lld waiting", waitingCount) : "") }
        if waitingCount > 0 { return trf("Waiting for user · %lld %@", waitingCount, waitingCount == 1 ? tr("task") : tr("tasks")) }
        return observedState == "Unknown" ? tr("No task reported") : tr(observedState)
    }

}

extension Array where Element == AgentBadgeState {
    /// Display order shared by Settings, Welcome, and the dashboard. Titles
    /// sort A–Z; Settings additionally puts locally detected agents first.
    func sortedForAgentDisplay(detectedFirst: Bool = false) -> [AgentBadgeState] {
        sorted { lhs, rhs in
            if detectedFirst, lhs.isDetected != rhs.isDetected {
                return lhs.isDetected
            }
            let comparison = lhs.title.localizedStandardCompare(rhs.title)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.provider < rhs.provider
        }
    }
}

struct SettingsAgentBadge: View {
    let state: AgentBadgeState
    let enabled: Bool
    var showsCLIInstallation = false
    let onToggle: @MainActor @Sendable (Bool) -> Void
    private var statusText: String {
        showsCLIInstallation ? state.installationText : state.compactDetail
    }
    private var accessibilityDescription: String {
        let selection = !enabled ? tr("Ignored for sleep") : state.workingCount > 0 ? tr("May delay sleep") : tr("No working tasks holding power")
        return selection + ". " + statusText + ". " + state.observationExplanation
    }
    private var mark: some View {
        AgentBadge(provider: state.provider, title: state.title,
                   tone: enabled ? .selected : .neutral)
    }
    private var badge: some View {
        Button {
            onToggle(!enabled)
        } label: {
            mark
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("camlid.agent." + state.provider)
        .accessibilityLabel(state.title)
        .accessibilityValue(accessibilityDescription)
        .accessibilityHint(enabled ? tr("Click to ignore this agent for sleep decisions")
            : tr("Click to include this agent in sleep decisions"))
        .accessibilityAddTraits(enabled ? .isSelected : [])
    }
    var body: some View {
        if let reason = state.settingsUnavailableReason {
            ZStack {
                badge
                    .disabled(true)
                    .blur(radius: 0.7)
                    .opacity(0.6)
                    .accessibilityHint(reason)
                // A sibling, not an overlay, so the disabled button's
                // environment cannot suppress the native hover tooltip.
                Capsule().fill(.clear).contentShape(Capsule())
                    .help(reason)
                    .accessibilityHidden(true)
            }
        } else {
            badge
        }
    }
}

enum AgentBadgeMetrics {
    /// The artwork itself. Kept smaller than the slot so the mark has breathing
    /// room inside the capsule.
    static let markSize: CGFloat = 20
    /// A fixed square slot shared by raster, vector, and fallback marks.
    static let markSlotSize: CGFloat = 28
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 5
}

/// Single badge shell for every surface that names an agent: Settings, Welcome,
/// and Dashboard. Surfaces only choose a tone and an optional trailing accessory.
struct AgentBadge<Accessory: View>: View {
    let provider: String
    let title: String
    var tone: CamLidPillTone = .neutral
    private let accessory: Accessory

    init(provider: String, title: String, tone: CamLidPillTone = .neutral,
         @ViewBuilder accessory: () -> Accessory) {
        self.provider = provider
        self.title = title
        self.tone = tone
        self.accessory = accessory()
    }

    var body: some View {
        BadgeShell(title: title, tone: tone, mark: {
            AgentMarkView(provider: provider, size: AgentBadgeMetrics.markSize)
        }, accessory: {
            accessory
        })
    }
}

/// The badge shell shared by agents and music sources: a mark, a name, then an optional accessory.
struct BadgeShell<Mark: View, Accessory: View>: View {
    let title: String
    var tone: CamLidPillTone = .neutral
    private let mark: Mark
    private let accessory: Accessory

    init(title: String, tone: CamLidPillTone = .neutral,
         @ViewBuilder mark: () -> Mark, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.tone = tone
        self.mark = mark()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            mark
                .frame(width: AgentBadgeMetrics.markSlotSize,
                       height: AgentBadgeMetrics.markSlotSize)
            Text(title).font(.callout).bold().lineLimit(1)
            accessory
        }
        .padding(.leading, 6)
        .padding(.trailing, AgentBadgeMetrics.horizontalPadding)
        .padding(.vertical, AgentBadgeMetrics.verticalPadding)
        .camLidPill(tone)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

extension AgentBadge where Accessory == EmptyView {
    init(provider: String, title: String, tone: CamLidPillTone = .neutral) {
        self.init(provider: provider, title: title, tone: tone) { EmptyView() }
    }
}

/// Dashboard badge: mark, name, then the primary activity status and count.
struct DashboardAgentBadge: View {
    let agent: AgentBadgeState

    private var isWorking: Bool { agent.workingCount > 0 }
    private var status: String { isWorking ? "Working" : "Waiting" }
    private var count: Int { isWorking ? agent.workingCount : agent.waitingCount }
    private func countText(_ value: Int) -> String {
        "\(value) " + (value == 1 ? tr("task") : tr("tasks"))
    }
    private var hoverText: String {
        guard isWorking else { return trf("Waiting: %@", countText(count)) }
        var text = trf("Working: %@", countText(count))
        if agent.waitingCount > 0 {
            text += trf(" · Waiting: %@", countText(agent.waitingCount))
        }
        return text
    }

    var body: some View {
        AgentBadge(provider: agent.provider, title: agent.title, tone: .activity) {
            Text(trf("%lld %@", count, tr(status.lowercased()))).font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help(hoverText)
        .accessibilityLabel(trf("%@, %@, %@", agent.title, tr(status), countText(count)))
        .accessibilityValue(agent.observationExplanation)
        .accessibilityIdentifier("camlid.observed." + agent.provider)
    }
}

/// Shared mode actions; unwired previews can choose a saved default.
struct ModeBadges: View {
    let selected: RequestedMode
    let onSelect: @MainActor @Sendable (RequestedMode) -> Void
    var activatesSession = false
    /// Auto needs at least one detection-enabled agent; Timed never does.
    var autoEnabled = true
    var body: some View {
        HStack(spacing: 5) {
            ForEach([RequestedMode.auto, .timed], id: \.self) { mode in
                Button { onSelect(mode) } label: {
                    // Primary text and the menu bar's own marks: grey text on grey read as disabled.
                    Label(buttonLabel(mode), systemImage: mode == .auto ? "arrow.triangle.2.circlepath" : "timer")
                        .font(.callout.weight(isSelected(mode) ? .semibold : .regular))
                        .foregroundStyle(isSelected(mode) ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .camLidPill(isSelected(mode) ? .selected : .neutral)
                        // Explicit colours do not dim with .disabled, so an unavailable Auto needs this to look unavailable.
                        .opacity(isUnavailable(mode) ? 0.4 : 1)
                }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(isSelected(mode) ? .isSelected : [])
                    .accessibilityValue(isSelected(mode) ? tr("Selected") : (isUnavailable(mode) ? tr("Unavailable") : tr("Not selected")))
                    .accessibilityLabel(accessibilityLabel(mode))
                    .accessibilityIdentifier("camlid.mode." + mode.rawValue)
                    .help(modeHelp(mode) + (isUnavailable(mode) ? tr(" Select an agent in Settings → Agents first.") : ""))
                    .disabled(isUnavailable(mode))
            }
        }.accessibilityElement(children: .contain)
            .accessibilityLabel(tr("Session mode"))
    }
    private var displayedSelection: RequestedMode { selected == .manual ? .timed : selected }
    /// Auto without a detection-enabled agent: dimmed and disabled, and the dashboard says why.
    private func isUnavailable(_ mode: RequestedMode) -> Bool { mode == .auto && !autoEnabled }
    private func isSelected(_ mode: RequestedMode) -> Bool {
        selected != .off && mode == displayedSelection
    }
    private func buttonLabel(_ mode: RequestedMode) -> String {
        tr(mode.rawValue.capitalized)
    }
    private func accessibilityLabel(_ mode: RequestedMode) -> String {
        guard activatesSession else { return trf("%@ mode", tr(mode.rawValue.capitalized)) }
        return isSelected(mode) ? trf("Stop %@ session", tr(mode.rawValue.capitalized)) : trf("Start %@ session", tr(mode.rawValue.capitalized))
    }
    private func modeHelp(_ mode: RequestedMode) -> String {
        if activatesSession, isSelected(mode) {
            return trf("Selected. Click again to stop the %@ session.", mode.rawValue.capitalized)
        }
        switch mode {
        case .off: return activatesSession ? tr("End the current session.") : tr("No session can start.")
        case .auto: return activatesSession ? tr("Start an Auto session; finish after selected agents and the completion delay.") : tr("Save Auto as the next session mode.")
        case .timed, .manual: return activatesSession ? tr("Start a Timed session with the timer choice; safety limits still apply.") : tr("Save Timed as the next session mode.")
        }
    }
}
