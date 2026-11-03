import SwiftUI

/// Semantic colors shared by status labels, notices, and compact chips.
enum CamLidTone {
    case neutral
    case info
    case accent
    case success
    case warning
    case danger

    var foreground: Color {
        switch self {
        case .neutral, .info: Color.secondary
        case .accent: Color.accentColor
        case .success: Color.green
        case .warning: Color.orange
        case .danger: Color.red
        }
    }

    var cardFill: Color {
        switch self {
        case .neutral, .info: Color.primary.opacity(0.05)
        case .accent: Color.accentColor.opacity(0.08)
        case .success: Color.green.opacity(0.08)
        case .warning: Color.orange.opacity(0.08)
        case .danger: Color.red.opacity(0.08)
        }
    }

    /// Informational text stays quiet; actionable states keep primary text so
    /// the tinted icon carries the color cue without reducing legibility.
    var text: Color {
        switch self {
        case .neutral, .info: Color.secondary
        case .accent, .success, .warning, .danger: Color.primary
        }
    }
}

/// Inline icon + message used for validation, preview, and status text.
struct CamLidStatusLabel: View {
    private let title: Text
    let systemImage: String
    let tone: CamLidTone
    var font: Font = .callout
    var help: String?

    init(_ title: String, systemImage: String, tone: CamLidTone = .neutral,
         font: Font = .callout, help: String? = nil) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.tone = tone
        self.font = font
        self.help = help
    }

    init(_ title: Text, systemImage: String, tone: CamLidTone = .neutral,
         font: Font = .callout, help: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.font = font
        self.help = help
    }

    private var label: some View {
        Label {
            title.foregroundStyle(tone.text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tone.foreground)
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder var body: some View {
        if let help {
            label.help(help)
        } else {
            label
        }
    }
}

/// Rounded notice surface for a title, optional detail, and optional action.
struct CamLidNoticeCard: View {
    let tone: CamLidTone
    let systemImage: String
    let title: String
    var message: String?
    var help: String?
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.cardFill, in: RoundedRectangle(cornerRadius: 8))
        .help(help ?? title)
    }
}

/// The compact, equal-width metric tile used by the dashboard health row.
struct CamLidMetricChip: View {
    let value: String
    let systemImage: String
    let detail: String
    var attention = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.caption).monospacedDigit()
            .foregroundStyle(attention ? Color.orange : Color.primary)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 6).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: Capsule())   // the same capsule as the mode buttons and agent badges
            .overlay { if contrast == .increased { Capsule().strokeBorder(Color.primary.opacity(0.55), lineWidth: 1) } }
            .help(detail)
            .accessibilityLabel(detail)
    }
}

/// Shared empty-state layout for lists and filtered lists.
struct CamLidEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}

/// One fill/stroke language for every selectable capsule in the app.
enum CamLidPillTone: Equatable {
    case neutral
    case selected
    case activity

    var fill: AnyShapeStyle {
        switch self {
        case .neutral: AnyShapeStyle(Color.primary.opacity(0.05))
        case .selected: AnyShapeStyle(Color.accentColor.opacity(0.12))
        case .activity: AnyShapeStyle(.quaternary)
        }
    }

    var stroke: Color {
        switch self {
        case .neutral: Color.primary.opacity(0.12)
        case .selected: Color.accentColor.opacity(0.55)
        case .activity: Color.primary.opacity(0.08)
        }
    }

    var strokeWidth: CGFloat {
        self == .selected ? 1.5 : 1
    }
}

private struct CamLidPillSurface: ViewModifier {
    let tone: CamLidPillTone
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(tone.fill, in: Capsule())
            // Increase Contrast: the hairline outline becomes a clear one.
            .overlay(Capsule().strokeBorder(contrast == .increased ? Color.primary.opacity(tone == .selected ? 0.9 : 0.55) : tone.stroke,
                                            lineWidth: contrast == .increased ? max(tone.strokeWidth, 1.5) : tone.strokeWidth))
            .contentShape(Capsule())
    }
}

extension View {
    func camLidPill(_ tone: CamLidPillTone) -> some View {
        modifier(CamLidPillSurface(tone: tone))
    }
}

/// The one preview-build message shared by the dashboard and Settings.
struct PreviewBuildNotice: View {
    /// Closed-lid readiness from the app; nil keeps the generic preview line (fixtures, before the first update).
    var text: String? = nil
    var font: Font = .callout

    private var ready: Bool { text?.hasPrefix("Closed lid ready") == true }

    var body: some View {
        CamLidStatusLabel(
            text ?? "Can’t keep your Mac awake",
            systemImage: ready ? "checkmark.circle" : "info.circle",
            tone: ready ? .success : .info,
            font: font,
            help: ready
                ? "Sessions can keep this Mac awake with the lid closed, within the safety limits."
                : "Closed lid isn’t available yet. Settings › Closed Lid shows what is missing."
        )
    }
}
