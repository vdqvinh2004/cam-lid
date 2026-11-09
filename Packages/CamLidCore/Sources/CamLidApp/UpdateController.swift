import AppKit
import Combine

public enum UpdatePhase: String, Codable, Sendable {
    case unavailable, ready, checking, current, available, offline, error, deferred
}

public struct UpdateSnapshot: Codable, Equatable, Sendable {
    public var phase: UpdatePhase
    public var reason: String
    public var version: String?
    public let installationAvailable = false
}

public struct UpdateSafetyContext: Equatable, Sendable {
    public var sessionActive = false
    public var agentWorkActive = false
    public var recoveryRequired = false
    public var unsavedSettings = false
    public init() {}
    public var blockingReason: String? {
        if recoveryRequired { return "recoveryRequired" }
        if sessionActive { return "sessionActive" }
        if agentWorkActive { return "agentWorkActive" }
        if unsavedSettings { return "unsavedSettings" }
        return nil
    }
}

enum UpdateProbeOutcome: Equatable {
    case current, available(String), noCompatibleUpdate, offline, failed
}

@MainActor protocol UpdateProbeDriver: AnyObject {
    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws
}

/// Information-only check against the project's GitHub releases. It has no download/install command.
@MainActor public final class UpdateController: ObservableObject {
    @Published public private(set) var snapshot: UpdateSnapshot
    /// Spec 021: the once-a-day check. Off by default, and an upgrade never turns it on.
    @Published public private(set) var automaticChecks: Bool
    static let automaticChecksKey = "CamLidAutomaticUpdateChecks"
    static let lastRequestKey = "CamLidLastUpdateRequest"
    static let automaticInterval: TimeInterval = 24 * 60 * 60
    private let safety: @MainActor () -> UpdateSafetyContext
    private let makeDriver: @MainActor () -> any UpdateProbeDriver
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private var driver: (any UpdateProbeDriver)?
    private var timer: Timer?
    private var pendingCheck = false
    private var inFlight = false
    private var lastOutcome: UpdateProbeOutcome?

    public convenience init(bundle: Bundle = .main, defaults: UserDefaults = .standard,
                            safety: @escaping @MainActor () -> UpdateSafetyContext) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        self.init(safety: safety, makeDriver: { GitHubReleaseDriver(currentVersion: version) }, defaults: defaults)
    }
    init(safety: @escaping @MainActor () -> UpdateSafetyContext,
         makeDriver: @escaping @MainActor () -> any UpdateProbeDriver,
         defaults: UserDefaults = .standard, now: @escaping @MainActor () -> Date = { Date() }) {
        self.safety = safety; self.makeDriver = makeDriver; self.defaults = defaults; self.now = now
        snapshot = UpdateSnapshot(phase: .ready, reason: "manualCheckReady")
        automaticChecks = defaults.bool(forKey: Self.automaticChecksKey)
        if automaticChecks { scheduleTimer() }
    }
    public var canCheck: Bool { !inFlight && snapshot.phase != .deferred }
    public func check() {
        pendingCheck = true
        resumeIfSafe()
    }
    public func refreshSafety() {
        if inFlight, let reason = safety().blockingReason {
            snapshot = UpdateSnapshot(phase: .deferred, reason: reason)
        } else if !inFlight, pendingCheck { resumeIfSafe() }
        else if !inFlight, snapshot.phase == .deferred, safety().blockingReason == nil, let lastOutcome {
            present(lastOutcome)
        }
    }
    /// Spec 021 (FR-001, SC-003): Off stops the hourly tick at once. A request already sent completes.
    public func setAutomaticChecks(_ on: Bool) {
        automaticChecks = on
        defaults.set(on, forKey: Self.automaticChecksKey)
        timer?.invalidate(); timer = nil
        if on { scheduleTimer() }
    }

    /// Spec 021 (FR-003): at most one request per 24 hours, counted from the last request of any kind. A session or a
    /// recovery waits; the next hourly tick tries again. Agent activity and unsaved Settings do not block it.
    func runScheduledCheckIfDue() {
        guard automaticChecks, !inFlight else { return }
        if let last = defaults.object(forKey: Self.lastRequestKey) as? Date, now().timeIntervalSince(last) < Self.automaticInterval {
            return
        }
        let context = safety()
        guard !context.sessionActive, !context.recoveryRequired else { return }
        startRequest()
    }

    var isScheduled: Bool { timer != nil }

    private func scheduleTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runScheduledCheckIfDue() }
        }
        timer.tolerance = 5 * 60
        self.timer = timer
    }

    private func resumeIfSafe() {
        guard !inFlight else { return }
        if let reason = safety().blockingReason {
            snapshot = UpdateSnapshot(phase: .deferred, reason: reason); return
        }
        startRequest()
    }

    private func startRequest() {
        pendingCheck = false; inFlight = true; lastOutcome = nil
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
        if let reason = safety().blockingReason { snapshot = UpdateSnapshot(phase: .deferred, reason: reason) }
        else { present(outcome) }
    }
    private func present(_ outcome: UpdateProbeOutcome) {
        switch outcome {
        case .current: snapshot = UpdateSnapshot(phase: .current, reason: "latestCompatibleVersion")
        case .available(let version):
            snapshot = UpdateSnapshot(phase: .available, reason: "updateAvailable", version: String(version.prefix(80)))
        case .noCompatibleUpdate: snapshot = UpdateSnapshot(phase: .unavailable, reason: "noCompatibleUpdate")
        case .offline: snapshot = UpdateSnapshot(phase: .offline, reason: "networkUnavailable")
        case .failed: snapshot = UpdateSnapshot(phase: .error, reason: "updateCheckFailed")
        }
    }
}
