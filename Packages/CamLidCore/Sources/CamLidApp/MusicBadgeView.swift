import SwiftUI
import AppKit
import CamLidCore

/// Music sources in Settings › Agents and on the Dashboard. They use the agents' badge shell. The mark is the installed
/// app's own icon, or a neutral glyph when no app exists. A browser has no single app, so it gets a generic globe.
extension MusicSource {
    /// The name on a chip or a badge. Browsers are one source because the Chromium browsers share one audio signal.
    var chipTitle: String {
        switch self {
        case .browser: "Browser"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    /// The app whose icon marks this source, or nil for a browser.
    var markBundleID: String? {
        self == .browser ? nil : bundleIDs.first
    }

    var symbolName: String {
        self == .browser ? "globe" : "music.note"
    }

    /// The sources whose app or browser is installed on this Mac, found by bundle identifier.
    static var installed: Set<MusicSource> {
        Set(allCases.filter { source in
            source.bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        })
    }
}

/// A music source's mark, the same size and tile as an agent's mark.
struct MusicMarkView: View {
    let source: MusicSource
    var size: CGFloat = AgentBadgeMetrics.markSize

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        Group {
            if let icon = Self.appIcon(for: source) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: source.symbolName).resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.22)
                    .frame(width: size, height: size)
                    .background(Color.primary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(tile)
        .overlay(tile.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    /// The icon of the app installed for this source, or nil when that app is not installed.
    static func appIcon(for source: MusicSource) -> NSImage? {
        guard let bundleID = source.markBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// A music source in Settings › Agents. Clicking it turns the source on or off, like an agent's badge.
struct MusicSourceChip: View {
    let source: MusicSource
    let enabled: Bool
    let onToggle: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!enabled)
        } label: {
            BadgeShell(title: source.chipTitle, tone: enabled ? .selected : .neutral, mark: {
                MusicMarkView(source: source, size: AgentBadgeMetrics.markSize)
            }, accessory: {
                EmptyView()
            })
        }
        .buttonStyle(.plain)
        .help(source.help)
        .accessibilityIdentifier("camlid.music." + source.rawValue)
        .accessibilityLabel(source.chipTitle)
        .accessibilityValue(enabled ? "Keeps Auto awake while it plays" : "Ignored for sleep")
        .accessibilityHint(enabled ? "Click to stop keeping Auto awake while it plays"
            : "Click to keep Auto awake while it plays")
        .accessibilityAddTraits(enabled ? .isSelected : [])
    }
}

/// Dashboard badge for a music source that plays now, shaped like an agent's activity badge.
struct DashboardMusicBadge: View {
    let source: MusicSource

    var body: some View {
        BadgeShell(title: source.chipTitle, tone: .activity, mark: {
            MusicMarkView(source: source, size: AgentBadgeMetrics.markSize)
        }, accessory: {
            Text("playing").font(.caption).foregroundStyle(.secondary)
        })
        .help("Playing: keeps an Auto session awake while it plays")
        .accessibilityLabel("\(source.chipTitle), playing")
        .accessibilityIdentifier("camlid.playing." + source.rawValue)
    }
}
