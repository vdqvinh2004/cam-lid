import SwiftUI

public struct UpdatesView: View {
    var preferredHeight: CGFloat { 175 }
    public let snapshot: UpdateSnapshot
    public let canCheck: Bool
    public let onCheck: () -> Void
    public init(snapshot: UpdateSnapshot, canCheck: Bool, onCheck: @escaping () -> Void) {
        self.snapshot = snapshot; self.canCheck = canCheck; self.onCheck = onCheck
    }
    public var body: some View {
        ScrollView {
            content
        }.frame(minWidth: 360, maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("camlid.updates.window")
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "arrow.down.circle").font(.headline).help(title)
            Text(detail).fixedSize(horizontal: false, vertical: true)
            if snapshot.phase == .available, let version = snapshot.version { Text("Available version: \(version)") }
            if snapshot.phase == .checking {
                ProgressView("Checking update information…").controlSize(.small)
                    .accessibilityLabel("Checking for updates")
            } else if snapshot.phase != .unavailable {
                HStack {
                    Text("Checks only; no installation.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates", action: onCheck)
                        .disabled(!canCheck).help(canCheck ? "Check the signed update feed" : detail)
                        .accessibilityIdentifier("camlid.updates.check")
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
    }
    var title: String {
        switch snapshot.phase {
        case .unavailable: "Updates unavailable"
        case .ready: "Check for updates"
        case .checking: "Checking for updates…"
        case .current: "You’re up to date"
        case .available: "Update available"
        case .offline: "Network unavailable"
        case .error: "Couldn’t check for updates"
        case .deferred: "Update check deferred"
        }
    }
    var detail: String {
        switch snapshot.reason {
        case "developerIDRequired": "Update checks are available in the signed release."
        case "trustedFeedRequired": "No trusted update feed is configured for this release."
        case "updateSigningKeyRequired": "The update verification key is unavailable. Try a signed release."
        case "noCompatibleUpdate": "The feed did not provide a compatible update. This does not confirm the latest version."
        case "sessionActive": "The check will resume after the current session ends."
        case "agentWorkActive": "The check will resume when agent work is no longer active or uncertain."
        case "recoveryRequired": "Resolve power recovery before checking for updates."
        case "unsavedSettings": "Resolve or discard pending edits in Settings before checking for updates."
        case "networkUnavailable": "Reconnect and try again. Your installed version is unchanged."
        case "updateCheckFailed": "The check failed. Your installed version is unchanged. Try again later."
        case "latestCompatibleVersion": "The feed confirms the latest compatible version is installed."
        case "updateAvailable": "A newer compatible version is available. Installation is unavailable in this preview."
        case "checkingSignedFeed": "Reading the signed feed; no download or installation."
        default: "Checks run only when you request them. No system profile is sent."
        }
    }
}
