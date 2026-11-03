import SwiftUI

public struct UpdatesView: View {
    var preferredHeight: CGFloat {
        snapshot.phase == .unavailable ? 120 : 185
    }
    public let snapshot: UpdateSnapshot
    public let canCheck: Bool
    public let onCheck: () -> Void
    public init(snapshot: UpdateSnapshot, canCheck: Bool, onCheck: @escaping () -> Void) {
        self.snapshot = snapshot; self.canCheck = canCheck; self.onCheck = onCheck
    }
    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    public var body: some View {
        ScrollView {
            content
        }.frame(minWidth: 360, maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityIdentifier("camlid.updates.window")
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The title stays in the primary colour; the tone colours only the symbol (grey text read as disabled).
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(updateTone.foreground)
            }
            .help(title)
            Text(detail).fixedSize(horizontal: false, vertical: true)
            Text("Installed version: \(installedVersion)").font(.callout).foregroundStyle(.secondary)
            if snapshot.phase == .available, let version = snapshot.version {
                Text("Available version: \(version)").font(.callout).foregroundStyle(.secondary)
            }
            if snapshot.phase == .checking {
                ProgressView("Checking update information…").controlSize(.small)
                    .accessibilityLabel("Checking for updates")
            } else if snapshot.phase != .unavailable {
                HStack {
                    Spacer()
                    if snapshot.phase == .available {
                        Button("Open Releases") { NSWorkspace.shared.open(GitHubReleaseDriver.releasesPage) }
                            .help("Opens the project's GitHub releases page in your browser")
                            .accessibilityIdentifier("camlid.updates.open")
                    }
                    Button("Check for Updates", action: onCheck)
                        .disabled(!canCheck).help(canCheck ? "Ask GitHub for the newest release" : detail)
                        .accessibilityIdentifier("camlid.updates.check")
                }
                Text("CamLid only checks when you ask; it never downloads or installs updates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private var symbol: String {
        switch snapshot.phase {
        case .unavailable, .ready: "arrow.down.circle"
        case .checking: "arrow.triangle.2.circlepath"
        case .current: "checkmark.circle.fill"
        case .available: "arrow.down.circle.fill"
        case .offline: "wifi.slash"
        case .error: "exclamationmark.triangle.fill"
        case .deferred: "clock.fill"
        }
    }
    private var updateTone: CamLidTone {
        switch snapshot.phase {
        case .current: .success
        case .available: .accent
        case .offline, .error, .deferred: .warning
        default: .neutral
        }
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
        case "noCompatibleUpdate": "No published release was found. This doesn’t confirm that your version is the latest."
        case "sessionActive": "CamLid will check after the current session ends."
        case "agentWorkActive": "CamLid will check when agents are no longer active."
        case "recoveryRequired": "Finish recovery first, then check for updates."
        case "unsavedSettings": "Finish the pending Settings change, then check for updates."
        case "networkUnavailable": "Reconnect to the internet, then try again. Your installed version hasn’t changed."
        case "updateCheckFailed": "The check didn’t complete. Your installed version hasn’t changed. Try again later."
        case "latestCompatibleVersion": "This is the newest published version."
        case "updateAvailable": "A newer version is available. Download it from the releases page, then reinstall the helper once."
        case "checkingReleases": "Asking GitHub for the newest release. Nothing is downloaded or installed."
        default: "CamLid checks only when you ask. It sends no account, no cookies and no system profile."
        }
    }
}
