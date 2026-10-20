import SwiftUI
import AppKit
import CamLidCore

/// Provider mark: official artwork rendered directly (no tile, no recolor),
/// except the monochrome OpenCode mark which renders as a template so it stays
/// legible in both appearances (black in light, white in dark). Generic glyph fallback.
struct AgentMarkView: View {
    let provider: String
    static func image(for provider: String) -> NSImage? {
        let name: String
        switch provider {
        case "orca", "codex", "claude": name = "agent-" + provider
        default: return nil
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.accessibilityDescription = provider
        return image
    }
    var body: some View {
        Group {
            if provider == "opencode" {
                // OpenCode terminal frame, redrawn from CC0 path data (even-odd frame).
                Path { path in
                    path.addRect(CGRect(x: 2, y: 0, width: 20, height: 24))
                    path.addRect(CGRect(x: 7, y: 4.8, width: 10, height: 14.4))
                }
                .fill(style: FillStyle(eoFill: true))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
            } else if let image = Self.image(for: provider) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "person.crop.circle").resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityHidden(true)
    }
}

public struct AgentBadgeState: Codable, Equatable, Identifiable, Sendable {
    public static let providers = ["orca", "codex", "opencode", "claude"]
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
    public init(provider: String, enabled: Bool, tasks: [AgentTask], evidenceAgeSeconds: Double? = nil, processCount: Int = 0, cliDetected: Bool? = nil, observationKnown: Bool = true) {
        self.provider = provider; detectionEnabled = enabled
        self.evidenceAgeSeconds = evidenceAgeSeconds
        self.processCount = min(20, max(0, processCount))
        self.cliDetected = cliDetected
        // Caller scopes rows using the normalized provider tuple.
        let rows = tasks
        workingCount = rows.filter { $0.state == .working }.count
        waitingCount = rows.filter { $0.state == .waiting }.count
        unknownCount = rows.filter { $0.state == .unknown }.count
        confidence = rows.isEmpty || rows.contains(where: { $0.confidence == .unknown }) ? "unknown" : rows.contains(where: { $0.confidence == .inferred }) ? "inferred" : "exact"
        readiness = rows.isEmpty ? "disconnected" : "connected"
        observedState = rows.isEmpty ? ((!observationKnown || processCount > 0) ? "Unknown" : "Not detected")
            : workingCount > 0 ? "Active" : unknownCount > 0 ? "Unknown"
            : waitingCount > 0 ? "Waiting" : (evidenceAgeSeconds.map { $0 > 15 } == true ? "Unknown" : "Inactive")
    }
    private enum CodingKeys: String, CodingKey {
        case provider, detectionEnabled, readiness, observedState, workingCount, waitingCount, unknownCount, evidenceAgeSeconds, confidence, processCount, cliDetected
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider); try c.encode(detectionEnabled, forKey: .detectionEnabled)
        try c.encode(readiness, forKey: .readiness); try c.encode(observedState, forKey: .observedState)
        try c.encode(workingCount, forKey: .workingCount); try c.encode(waitingCount, forKey: .waitingCount)
        try c.encode(unknownCount, forKey: .unknownCount); try c.encode(evidenceAgeSeconds, forKey: .evidenceAgeSeconds)
        try c.encode(confidence, forKey: .confidence); try c.encode(processCount ?? 0, forKey: .processCount)
        try c.encodeIfPresent(cliDetected, forKey: .cliDetected)
    }
    var title: String { switch provider { case "orca": "Orca"; case "opencode": "OpenCode"; default: provider.capitalized } }
    var isDetected: Bool { (processCount ?? 0) > 0 || readiness == "connected" }
    var installationText: String { cliDetected.map { $0 ? "CLI detected" : "CLI not detected" } ?? "Checking CLI…" }
    /// Bundled raster mark, if this provider ships one. OpenCode renders as a vector
    /// below; unknown providers get the generic glyph.
    var markAssetName: String? {
        switch provider {
        case "orca", "codex", "claude": "agent-" + provider
        default: nil
        }
    }
    /// Providers whose mark is drawn in code rather than bundled raster art.
    var usesVectorMark: Bool { provider == "opencode" }
    var detail: String { readiness == "disconnected" && (processCount ?? 0) > 0 ? "Process found · task state unknown" : workingCount > 0 ? compactDetail + (unknownCount > 0 ? " · \(unknownCount) unknown" : "") : waitingCount > 0 ? compactDetail : observedState }
    var observationExplanation: String {
        let receipt: String
        if let age = evidenceAgeSeconds, age.isFinite, age >= 0 {
            receipt = age >= 3_600 ? "Latest source receipt at least 1 hr ago; not task-state age."
                : "Latest source receipt: \(age.formatted(.number.precision(.fractionLength(0))))s ago; not task-state age."
        } else {
            receipt = "Source receipt age unavailable."
        }
        let qualification = provider == "orca"
            ? "Orca reports pane state. State freshness is unverified; this does not prove all jobs have finished."
            : "Process presence alone does not prove activity or completion."
        return "Reported confidence: \(confidence). \(receipt) \(qualification) Tasks waiting for the user never keep the machine awake."
    }
    static func workingSummary(_ agents: [Self]) -> String {
        let count = agents.filter { $0.detectionEnabled && $0.workingCount > 0 }.count
        return count == 0 ? "No selected agents reporting work"
            : count == 1 ? "1 selected agent reporting work" : "\(count) selected agents reporting work"
    }
    static func waitingSummary(_ agents: [Self]) -> String {
        let count = agents.filter { $0.detectionEnabled && $0.workingCount == 0 && $0.waitingCount > 0 }.count
        return count == 0 ? "No selected agents waiting for user"
            : count == 1 ? "1 selected agent waiting for user" : "\(count) selected agents waiting for user"
    }
    var compactDetail: String {
        if readiness == "disconnected" { return observedState == "Unknown" ? "Task unknown" : "Not detected" }
        if workingCount > 0 { return "Active · \(workingCount) " + (workingCount == 1 ? "task" : "tasks") + (waitingCount > 0 ? " · \(waitingCount) waiting" : "") }
        if waitingCount > 0 { return "Waiting for user · \(waitingCount) " + (waitingCount == 1 ? "task" : "tasks") }
        return observedState == "Unknown" ? "Task unknown" : observedState
    }

}

struct AgentBadgeView: View {
    let state: AgentBadgeState
    let enabled: Bool
    var showsCLIInstallation = false
    let onToggle: @MainActor @Sendable (Bool) -> Void
    private var selectionHelp: String {
        let action = enabled ? "Click to ignore \(state.title) for sleep decisions. " : "Click to include \(state.title) in sleep decisions. "
        return action + state.observationExplanation
    }
    private var accessibilityDescription: String {
        let selection = !enabled ? "Ignored for sleep, " : state.workingCount > 0 ? "May delay sleep, " : "No working tasks holding power, "
        let status = showsCLIInstallation ? state.installationText : state.detail
        return selection + status + ". " + state.observationExplanation
    }
    var body: some View {
        Button { onToggle(!enabled) } label: {
            HStack(alignment: .center, spacing: 8) {
                AgentMarkView(provider: state.provider).help(state.title)
                Text(state.title).font(.callout).bold()
                Spacer(minLength: 8)
                if showsCLIInstallation {
                    Text(state.installationText).font(.callout).foregroundStyle(.secondary)
                        .help("Checks executable installation on this Mac")
                } else if state.workingCount > 0 || state.waitingCount > 0 {
                    HStack(spacing: 6) {
                        if state.waitingCount > 0 {
                            Label("\(state.waitingCount)", systemImage: "hourglass")
                                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                                .help("\(state.waitingCount) tasks waiting for user in \(state.title). Waiting never holds power.")
                        }
                        if state.workingCount > 0 {
                            Label("\(state.workingCount)", systemImage: "terminal")
                                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                                .help("\(state.workingCount) working tasks reported by \(state.title)")
                        }
                    }
                } else {
                    Text(state.compactDetail).font(.callout).foregroundStyle(.secondary)
                }
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                    .help(!enabled ? "Ignored for sleep" : state.workingCount > 0 ? "May delay sleep" : "No working tasks holding power")
                    .accessibilityHidden(true)
            }
                .padding(10)
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .background(enabled ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(enabled ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: enabled ? 2 : 1))
        }
        .buttonStyle(.borderless)
        .help(selectionHelp)
        .accessibilityIdentifier("camlid.agent." + state.provider)
        .accessibilityLabel(state.title)
        .accessibilityValue(accessibilityDescription)
        .accessibilityAddTraits(enabled ? .isSelected : [])
        .accessibilityHint("Choose whether this agent may delay sleep")
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
                    Text(mode.rawValue.capitalized).font(.callout)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(mode == displayedSelection ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: Capsule())
                        .overlay(Capsule().strokeBorder(mode == displayedSelection ? Color.accentColor : Color.clear, lineWidth: 2))
                        .contentShape(Capsule())
                }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(mode == displayedSelection ? .isSelected : [])
                    .accessibilityValue(mode == displayedSelection ? "Selected" : "Not selected")
                    .accessibilityLabel(mode.rawValue.capitalized + " mode")
                    .accessibilityIdentifier("camlid.mode." + mode.rawValue)
                    .help(modeHelp(mode) + (mode == .auto && !autoEnabled ? " Select an agent in Settings → Agents first." : ""))
                    .disabled(mode == .auto && !autoEnabled)
            }
        }.accessibilityElement(children: .contain)
            .accessibilityLabel("Session mode")
    }
    private var displayedSelection: RequestedMode { selected == .manual ? .timed : selected }
    private func modeHelp(_ mode: RequestedMode) -> String {
        if activatesSession, mode == displayedSelection, mode != .off { return "Click again to turn Off." }
        switch mode {
        case .off: return activatesSession ? "End the current session." : "No session can start."
        case .auto: return activatesSession ? "Start Auto; finish after selected agents and the completion delay." : "Save Auto as the next session mode."
        case .timed, .manual: return activatesSession ? "Start with the timer choice; safety limits still apply." : "Save Timed as the next session mode."
        }
    }
}
