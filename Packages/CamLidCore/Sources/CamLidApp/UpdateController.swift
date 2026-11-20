import AppKit
import CamLidCore
import Combine

public enum UpdatePhase: String, Codable, Sendable {
    case unavailable, ready, checking, current, available, offline, error, deferred, preparing, installing
}

public struct UpdateSnapshot: Codable, Equatable, Sendable {
    public var phase: UpdatePhase
    public var reason: String
    public var version: String?
}

public struct UpdateSafetyContext: Equatable, Sendable {
    public var sessionActive = false
    public var recoveryRequired = false
    public var unsavedSettings = false
    public init() {}
    /// Spec 026 FR-003: what holds an install. A recovery must finish and unsaved Settings must be saved first. A running
    /// session does not hold it: the user is asked to stop it. Agent activity never holds it.
    public var blockingReason: String? {
        if recoveryRequired { return "recoveryRequired" }
        if unsavedSettings { return "unsavedSettings" }
        return nil
    }
    /// Spec 021: only a recovery holds a check. A session, agent work and unsaved Settings do not: a check changes nothing on
    /// the Mac; it only asks GitHub.
    public var checkBlockingReason: String? {
        if recoveryRequired { return "recoveryRequired" }
        return nil
    }
}

enum UpdateProbeOutcome: Equatable {
    case current, available(String, UpdateAssets?), noCompatibleUpdate, offline, failed
}

@MainActor protocol UpdateProbeDriver: AnyObject {
    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws
}

/// The check reads the project's GitHub releases and downloads nothing. An install starts only from the Update button
/// (spec 026), and only after the release has been checked.
@MainActor public final class UpdateController: ObservableObject {
    @Published public private(set) var snapshot: UpdateSnapshot
    /// Spec 021: the once-a-day check. Off by default, and an upgrade never turns it on.
    @Published public private(set) var automaticChecks: Bool
    static let automaticChecksKey = "CamLidAutomaticUpdateChecks"
    static let lastRequestKey = "CamLidLastUpdateRequest"
    static let automaticInterval: TimeInterval = 24 * 60 * 60
    private let safety: @MainActor () -> UpdateSafetyContext
    private let makeDriver: @MainActor () -> any UpdateProbeDriver
    private let installer: any UpdateInstalling
    private let defaults: any PreferenceStore
    private let now: @MainActor () -> Date
    private let currentVersion: String
    private var driver: (any UpdateProbeDriver)?
    private var timer: Timer?
    private var pendingCheck = false
    private var inFlight = false
    private var lastOutcome: UpdateProbeOutcome?
    /// Spec 026: the zip and checksum of the release the last check offered. Nil when the release has neither.
    private var pendingAssets: UpdateAssets?
    /// The swap script of the install in progress, so a quit that stays cancelled can stop it.
    private var launchedScriptPID: Int32?
    /// Called once the swap script is running. The caller ends a session the user agreed to end, then the app quits.
    var onInstallLaunched: (@MainActor () -> Void)?

    /// The app's controller: the bundled version, the GitHub driver, and the installer for `home` (the real home, or a QA folder).
    convenience init(home: URL, defaults: any PreferenceStore = UserDefaults.standard,
                     safety: @escaping @MainActor () -> UpdateSafetyContext) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        self.init(safety: safety, makeDriver: { GitHubReleaseDriver(currentVersion: version) },
                  installer: UpdateInstaller(home: home), defaults: defaults, currentVersion: version)
    }
    init(safety: @escaping @MainActor () -> UpdateSafetyContext,
         makeDriver: @escaping @MainActor () -> any UpdateProbeDriver,
         installer: any UpdateInstalling = NoUpdateInstaller(),
         defaults: any PreferenceStore = UserDefaults.standard, now: @escaping @MainActor () -> Date = { Date() },
         currentVersion: String = "0.0.0") {
        self.safety = safety; self.makeDriver = makeDriver; self.installer = installer; self.defaults = defaults
        self.now = now; self.currentVersion = currentVersion
        snapshot = UpdateSnapshot(phase: .ready, reason: "manualCheckReady")
        automaticChecks = defaults.bool(forKey: Self.automaticChecksKey)
        if automaticChecks { scheduleTimer() }
    }
    /// A check can be asked for unless one is running or a recovery holds it (spec 021).
    public var canCheck: Bool { !inFlight && safety().checkBlockingReason == nil }
    /// Spec 026: the Update button is offered for an available release with known assets, in a build that can install, while
    /// no recovery or unsaved Settings holds it. The release itself stays shown (the notice depends on it).
    public var canInstall: Bool {
        snapshot.phase == .available && pendingAssets != nil && installer.canInstall && !Self.installBlockers.contains(snapshot.reason)
    }
    /// The blockers an install waits for. A running session is not one: the user is asked to stop it instead.
    static let installBlockers: Set<String> = ["recoveryRequired", "unsavedSettings"]
    public func check() {
        pendingCheck = true
        resumeIfSafe()
    }
    /// Runs on each coordinator refresh (about once a second): a deferred check resumes when its blocker clears, and a
    /// release whose install was waiting is offered again.
    public func refreshSafety() {
        if !inFlight, pendingCheck { resumeIfSafe() }
        else if !inFlight, snapshot.phase == .deferred, safety().checkBlockingReason == nil, let lastOutcome {
            present(lastOutcome)
        } else if !inFlight, snapshot.phase == .available {
            // The reason names the install blocker that holds the release, and clears back to "updateAvailable" by itself.
            if let blocker = safety().blockingReason {
                if snapshot.reason != blocker { snapshot = UpdateSnapshot(phase: .available, reason: blocker, version: snapshot.version) }
            } else if Self.installBlockers.contains(snapshot.reason) {
                snapshot = UpdateSnapshot(phase: .available, reason: "updateAvailable", version: snapshot.version)
            }
        }
    }
    /// Spec 026 FR-001 to FR-003: a click on Update. A recovery or unsaved Settings holds it, and the release stays offered
    /// with the reason. A running session is ended only when the user agreed to that (`endingSession`); the caller ends it
    /// right before the restart, after the download and checks have passed. Then the release is downloaded, checked, and
    /// handed to the swap script, and the app quits.
    public func installAvailable(endingSession: Bool) {
        guard canInstall, let assets = pendingAssets, let version = snapshot.version,
              let current = ReleaseVersion(currentVersion) else { return }
        if let reason = safety().blockingReason { snapshot = UpdateSnapshot(phase: .available, reason: reason, version: version); return }
        // Without the user's agreement a running session is never ended, so the click does nothing.
        guard !safety().sessionActive || endingSession else { return }
        snapshot = UpdateSnapshot(phase: .preparing, reason: "downloadingUpdate", version: version)
        installer.install(assets, version: version, current: current) { [weak self] outcome in self?.finishInstall(outcome) }
    }
    /// The app stayed open after the swap was launched, because a quit was refused (for example while Settings are still being
    /// saved). The swap script is stopped, so the update cannot apply later without the user, and the reason is shown.
    public func installQuitWasCancelled(reason: String = "quitCancelled") {
        guard snapshot.phase == .installing, let pid = launchedScriptPID else { return }
        launchedScriptPID = nil
        installer.cancelLaunch(pid)
        snapshot = UpdateSnapshot(phase: .error, reason: reason, version: snapshot.version)
    }
    /// Spec 021 (FR-001, SC-003): Off stops the hourly tick at once. A request already sent completes.
    public func setAutomaticChecks(_ on: Bool) {
        automaticChecks = on
        defaults.set(on, forKey: Self.automaticChecksKey)
        timer?.invalidate(); timer = nil
        if on { scheduleTimer() }
    }

    /// Spec 021 (FR-003): at most one request per 24 hours, counted from the last request of any kind. A recovery waits;
    /// the next hourly tick tries again. A session, agent activity and unsaved Settings do not block it.
    func runScheduledCheckIfDue() {
        guard automaticChecks, !inFlight else { return }
        if let last = defaults.object(forKey: Self.lastRequestKey) as? Date, now().timeIntervalSince(last) < Self.automaticInterval {
            return
        }
        guard safety().checkBlockingReason == nil else { return }
        startRequest()
    }

    var isScheduled: Bool { timer != nil }

    private func scheduleTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runScheduledCheckIfDue() }
        }
        timer.tolerance = 5 * 60
        self.timer = timer
        // A check that is already due runs soon after the setting is turned on or the app starts, not an hour later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.runScheduledCheckIfDue()
        }
    }

    private func resumeIfSafe() {
        guard !inFlight else { return }
        if let reason = safety().checkBlockingReason {
            snapshot = UpdateSnapshot(phase: .deferred, reason: reason); return
        }
        startRequest()
    }

    private func startRequest() {
        pendingCheck = false; inFlight = true; lastOutcome = nil; pendingAssets = nil
        snapshot = UpdateSnapshot(phase: .checking, reason: "checkingReleases")
        let driver = driver ?? makeDriver(); self.driver = driver
        do {
            try driver.checkInformation { [weak self] outcome in self?.finish(outcome) }
            defaults.set(now(), forKey: Self.lastRequestKey)
        } catch { finish(.failed) }
    }
    private func finish(_ outcome: UpdateProbeOutcome) {
        guard inFlight else { return }
        inFlight = false; lastOutcome = outcome
        // Repeated clicks during a check do not queue another network request.
        pendingCheck = false
        // A finished result is shown even during a session, so a known release stays installable with the user's agreement.
        // Only a recovery holds it back.
        if safety().recoveryRequired { snapshot = UpdateSnapshot(phase: .deferred, reason: "recoveryRequired") }
        else { present(outcome) }
    }
    private func finishInstall(_ outcome: UpdateInstallOutcome) {
        switch outcome {
        case .launched(let pid):
            launchedScriptPID = pid
            snapshot = UpdateSnapshot(phase: .installing, reason: "installingUpdate", version: snapshot.version)
            onInstallLaunched?()
        case .failed(let reason):
            pendingAssets = nil
            snapshot = UpdateSnapshot(phase: .error, reason: reason, version: snapshot.version)
        }
    }
    private func present(_ outcome: UpdateProbeOutcome) {
        switch outcome {
        case .current: snapshot = UpdateSnapshot(phase: .current, reason: "latestCompatibleVersion")
        case .available(let version, let assets):
            pendingAssets = assets
            // The release is shown at once. A recovery or unsaved Settings is named in the reason until it clears (spec 026).
            snapshot = UpdateSnapshot(phase: .available, reason: safety().blockingReason ?? "updateAvailable",
                                      version: String(version.prefix(80)))
        case .noCompatibleUpdate: snapshot = UpdateSnapshot(phase: .unavailable, reason: "noCompatibleUpdate")
        case .offline: snapshot = UpdateSnapshot(phase: .offline, reason: "networkUnavailable")
        case .failed: snapshot = UpdateSnapshot(phase: .error, reason: "updateCheckFailed")
        }
    }
}
