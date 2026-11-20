import SwiftUI

/// The Updates window (specs 021 and 026). It says what CamLid found and what happens next, and offers the one action that fits:
/// Update when the install can run (asking first while a session runs), the same button disabled with its reason while a
/// recovery or unsaved Settings holds it, and Check for Updates whenever a check can be asked for.
public struct UpdatesView: View {
    public let snapshot: UpdateSnapshot
    public let canCheck: Bool
    /// Spec 026: the install can run when the release has its assets and this build can install.
    public let canInstall: Bool
    /// A session is running. Installing asks first, and ends the session only if the user agrees.
    public let sessionActive: Bool
    public let installedVersion: String
    public let onCheck: () -> Void
    /// Called with `true` when the user agreed to end the running session for the install.
    public let onInstall: (Bool) -> Void
    @State private var confirmingInstall = false

    public init(snapshot: UpdateSnapshot, canCheck: Bool, canInstall: Bool = false, sessionActive: Bool = false,
                installedVersion: String = UpdatesView.bundleVersion, onCheck: @escaping () -> Void,
                onInstall: @escaping (Bool) -> Void = { _ in }) {
        self.snapshot = snapshot; self.canCheck = canCheck; self.canInstall = canInstall; self.sessionActive = sessionActive
        self.installedVersion = installedVersion; self.onCheck = onCheck; self.onInstall = onInstall
    }
    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    /// The blockers that hold an install (spec 026 FR-003). A session is not one: the user is asked to stop it instead.
    private static let installBlockers: Set<String> = ["recoveryRequired", "unsavedSettings"]

    private var availableVersion: String { snapshot.version ?? "" }
    private var isBusy: Bool { [.checking, .preparing, .installing].contains(snapshot.phase) }
    /// A release is known, but a recovery or unsaved Settings holds its install. Update stays visible, disabled, with the reason.
    var isWaitingToInstall: Bool { snapshot.phase == .available && Self.installBlockers.contains(snapshot.reason) }
    /// Update is shown when the install can run now, or when it only waits for a blocker to clear.
    var showsUpdateButton: Bool { snapshot.phase == .available && (canInstall || isWaitingToInstall) }
    var updateButtonEnabled: Bool { canInstall }
    /// The buttons stay up for every state except a running check or install.
    var showsButtons: Bool { !isBusy }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(detail).fixedSize(horizontal: false, vertical: true)
            if isBusy {
                // The body already says what is happening; the spinner only needs a label for VoiceOver.
                ProgressView().controlSize(.small).accessibilityLabel(busyText)
            }
            if showsButtons { buttons }
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 460, maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("camlid.updates.window")
        .alert(alertTitle, isPresented: $confirmingInstall) {
            if sessionActive {
                Button(tr("Stop Session and Install")) { onInstall(true) }
            } else {
                Button(tr("Install and Restart")) { onInstall(false) }
            }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        sessionActive ? trf("Stop the session and install CamLid %@?", availableVersion) : trf("Install CamLid %@?", availableVersion)
    }
    private var alertMessage: String {
        sessionActive
            ? tr("A session is keeping the Mac awake. CamLid downloads and checks the release first. If that passes, the session stops, CamLid restarts with the new version, and the Mac can then sleep. If a check fails, the session keeps running and nothing is changed.")
            : tr("CamLid downloads the release from GitHub, checks its checksum and its signature, replaces the app and starts the new version. Your settings are kept. If a check fails, nothing is changed.")
    }

    private var header: some View {
        // The title stays in the primary colour; the tone colours only the symbol, which VoiceOver does not need to read.
        Label {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
        } icon: {
            Image(systemName: symbol).foregroundStyle(updateTone.foreground).accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()
            if snapshot.phase == .available {
                Button(tr("Open Releases")) { NSWorkspace.shared.open(GitHubReleaseDriver.releasesPage) }
                    .help(tr("Opens the project's GitHub releases page in your browser"))
                    .accessibilityIdentifier("camlid.updates.open")
            }
            Button(tr("Check for Updates"), action: onCheck)
                .disabled(!canCheck)
                .help(canCheck ? tr("Ask GitHub for the newest release") : checkWaitHelp)
                .accessibilityIdentifier("camlid.updates.check")
            if showsUpdateButton {
                Button(trf("Update to %@", availableVersion)) { confirmingInstall = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!updateButtonEnabled)
                    .help(updateButtonEnabled ? installHelp : detail)
                    .accessibilityHint(updateButtonEnabled ? "" : detail)
                    .accessibilityIdentifier("camlid.updates.install")
            }
        }
    }
    private var installHelp: String {
        sessionActive
            ? tr("Asks first, then ends the running session and restarts CamLid with the new version")
            : tr("Downloads the release, checks it, then replaces CamLid and restarts")
    }
    /// Why Check is off while buttons are shown: only a recovery holds checks (spec 021).
    private var checkWaitHelp: String { tr("Finish recovery first, then check for updates.") }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trf("Installed version %@", installedVersion))
            Text(tr("Checks ask GitHub only when you click Check for Updates, or once a day if the daily check is on. They send no account, no cookies and no system profile. Downloads start only when you click Update."))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var busyText: String {
        switch snapshot.phase {
        case .preparing: tr("Downloading and checking the update…")
        case .installing: tr("Installing and restarting…")
        default: tr("Checking update information…")
        }
    }
    private var symbol: String {
        switch snapshot.phase {
        case .unavailable, .ready: "arrow.down.circle"
        case .checking: "arrow.triangle.2.circlepath"
        case .preparing: "arrow.down.circle"
        case .installing: "arrow.triangle.2.circlepath"
        case .current: "checkmark.circle.fill"
        case .available: isWaitingToInstall ? "clock.fill" : "arrow.down.circle.fill"
        case .offline: "wifi.slash"
        case .error: "exclamationmark.triangle.fill"
        case .deferred: "clock.fill"
        }
    }
    private var updateTone: CamLidTone {
        switch snapshot.phase {
        case .current: .success
        case .available: isWaitingToInstall ? .neutral : .accent
        case .offline, .error, .deferred: .warning
        default: .neutral
        }
    }
    var title: String {
        switch snapshot.phase {
        case .unavailable: tr("Updates unavailable")
        case .ready: tr("Ready to check")
        case .checking: tr("Checking for updates…")
        case .current: tr("You’re up to date")
        case .available: tr("Update available")
        case .offline: tr("Network unavailable")
        case .error: snapshot.reason == "updateCheckFailed" ? tr("Couldn’t check for updates") : tr("Couldn’t install the update")
        case .deferred: tr("Update check deferred")
        case .preparing: tr("Preparing the update…")
        case .installing: tr("Installing the update…")
        }
    }
    /// The body text: one or two sentences the user can act on, for every state.
    var detail: String {
        snapshot.phase == .available ? availableDetail : checkDetail
    }
    /// A release is known: say which version, what holds the install, or what the Update button does.
    private var availableDetail: String {
        let found = trf("Version %@ is available; you have %@.", availableVersion, installedVersion)
        switch snapshot.reason {
        case "recoveryRequired": return trf("%@ Installing waits until recovery is finished.", found)
        case "unsavedSettings": return trf("%@ Installing waits until the pending Settings change is saved.", found)
        default:
            guard canInstall else { return trf("%@ Download it from the releases page and replace the app.", found) }
            return sessionActive
                ? trf("%@ Installing stops the running session first. You will be asked to confirm.", found)
                : trf("%@ Click Update to download, check and install it. CamLid restarts when the install is done.", found)
        }
    }
    private var checkDetail: String {
        switch snapshot.reason {
        case "noCompatibleUpdate": tr("No published release was found. This doesn’t confirm that your version is the latest.")
        case "recoveryRequired": tr("Finish recovery first, then check for updates.")
        case "networkUnavailable": tr("Reconnect to the internet, then try again. Your installed version hasn’t changed.")
        case "updateCheckFailed": tr("The check didn’t complete. Your installed version hasn’t changed. Try again later.")
        case "quitCancelled": tr("CamLid stayed open, so the update did not start. Finish any pending Settings change, then check for updates and click Update again.")
        case "sessionNotAgreed": tr("A session started while the update was downloading, so CamLid stayed open. Check for updates and click Update again to end that session too.")
        case "latestCompatibleVersion": trf("CamLid %@ is the newest published version.", installedVersion)
        case "checkingReleases": tr("Asking GitHub for the newest release. Nothing is downloaded or installed.")
        case "downloadingUpdate": tr("Downloading the release from GitHub. CamLid checks it before it replaces the app.")
        case "installingUpdate": tr("CamLid restarts with the new version.")
        case "updateNotWritable": tr("CamLid can’t replace the app in its folder. Download the release from the releases page instead.")
        case "updateChecksumMismatch": tr("The download didn’t match its published checksum. Nothing was changed.")
        case "updateSignerMismatch", "updateSignatureInvalid", "updateIdentifierMismatch", "updateVersionMismatch",
             "updateNotNewer", "updateBundleMissing", "updateUnpackFailed", "updateChecksumUnreadable", "updateDownloadFailed",
             "updateStagingFailed", "updateLaunchFailed":
            tr("The update was not installed, and the app was not changed. Try again later, or download the release from the releases page.")
        default: tr("Ask GitHub for the newest published release. Nothing is downloaded or installed.")
        }
    }
}
