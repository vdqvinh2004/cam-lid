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
    private let safety: @MainActor () -> UpdateSafetyContext
    private let makeDriver: @MainActor () -> any UpdateProbeDriver
    private var driver: (any UpdateProbeDriver)?
    private var pendingCheck = false
    private var inFlight = false
    private var lastOutcome: UpdateProbeOutcome?

    public convenience init(bundle: Bundle = .main, safety: @escaping @MainActor () -> UpdateSafetyContext) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        self.init(safety: safety, makeDriver: { GitHubReleaseDriver(currentVersion: version) })
    }
    init(safety: @escaping @MainActor () -> UpdateSafetyContext,
         makeDriver: @escaping @MainActor () -> any UpdateProbeDriver) {
        self.safety = safety; self.makeDriver = makeDriver
        snapshot = UpdateSnapshot(phase: .ready, reason: "manualCheckReady")
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
    private func resumeIfSafe() {
        guard !inFlight else { return }
        if let reason = safety().blockingReason {
            snapshot = UpdateSnapshot(phase: .deferred, reason: reason); return
        }
        pendingCheck = false; inFlight = true; lastOutcome = nil
        snapshot = UpdateSnapshot(phase: .checking, reason: "checkingReleases")
        let driver = driver ?? makeDriver(); self.driver = driver
        do { try driver.checkInformation { [weak self] outcome in self?.finish(outcome) } }
        catch { finish(.failed) }
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
