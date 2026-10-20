import AppKit
import Combine
import Security
import Sparkle

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

/// Distribution metadata comes from the signed bundle, never writable preferences.
public struct UpdateEligibility: Equatable, Sendable {
    public let reason: String?
    public var permitsCheck: Bool { reason == nil }
    public init(feedURL: String?, publicKey: String?, developerIDSigned: Bool) {
        guard developerIDSigned else { reason = "developerIDRequired"; return }
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil else { reason = "trustedFeedRequired"; return }
        guard let publicKey, let key = Data(base64Encoded: publicKey), key.count == 32 else {
            reason = "updateSigningKeyRequired"; return
        }
        reason = nil
    }
    static func bundle(_ bundle: Bundle) -> Self {
        let expectedTeam = bundle.object(forInfoDictionaryKey: "CamLidUpdateTeamID") as? String
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var signed = false
        if let expectedTeam, !expectedTeam.isEmpty,
           bundle.bundleIdentifier == "com.camlid.CamLid",
           SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &code) == errSecSuccess,
           SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
           let code, let requirement,
           SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess {
            var info: CFDictionary?
            if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
               let dictionary = info as? [String: Any] {
                signed = dictionary[kSecCodeInfoTeamIdentifier as String] as? String == expectedTeam
            }
        }
        return Self(feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                    publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                    developerIDSigned: signed)
    }
}

enum UpdateProbeOutcome: Equatable {
    case current, available(String), noCompatibleUpdate, offline, failed
}

@MainActor protocol UpdateProbeDriver: AnyObject {
    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws
}

/// Information-only Sparkle integration. It has no download/install command.
@MainActor public final class UpdateController: ObservableObject {
    @Published public private(set) var snapshot: UpdateSnapshot
    private let eligibility: UpdateEligibility
    private let safety: @MainActor () -> UpdateSafetyContext
    private let makeDriver: @MainActor () -> any UpdateProbeDriver
    private var driver: (any UpdateProbeDriver)?
    private var pendingCheck = false
    private var inFlight = false
    private var lastOutcome: UpdateProbeOutcome?

    public convenience init(bundle: Bundle = .main, safety: @escaping @MainActor () -> UpdateSafetyContext) {
        self.init(eligibility: .bundle(bundle), safety: safety,
                  makeDriver: { SparkleInformationDriver(safety: safety) })
    }
    init(eligibility: UpdateEligibility, safety: @escaping @MainActor () -> UpdateSafetyContext,
         makeDriver: @escaping @MainActor () -> any UpdateProbeDriver) {
        self.eligibility = eligibility; self.safety = safety; self.makeDriver = makeDriver
        snapshot = UpdateSnapshot(phase: eligibility.permitsCheck ? .ready : .unavailable,
                                  reason: eligibility.reason ?? "manualCheckReady")
    }
    public var canCheck: Bool { eligibility.permitsCheck && !inFlight && snapshot.phase != .deferred }
    public func check() {
        guard eligibility.permitsCheck else { return }
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
        snapshot = UpdateSnapshot(phase: .checking, reason: "checkingSignedFeed")
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

@MainActor private final class SparkleInformationDriver: NSObject, UpdateProbeDriver, SPUUpdaterDelegate {
    private let safety: @MainActor () -> UpdateSafetyContext
    private var controller: SPUStandardUpdaterController?
    private var completion: (@MainActor (UpdateProbeOutcome) -> Void)?
    private var outcome: UpdateProbeOutcome?
    init(safety: @escaping @MainActor () -> UpdateSafetyContext) { self.safety = safety }
    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws {
        if controller == nil {
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            try controller.updater.start()
            self.controller = controller
        }
        guard let updater = controller?.updater, updater.canCheckForUpdates else {
            throw NSError(domain: "CamLid.Updates", code: 1)
        }
        self.completion = completion; outcome = nil
        updater.checkForUpdateInformation()
    }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updateInformation, safety().blockingReason == nil else {
            throw NSError(domain: "CamLid.Updates", code: 2)
        }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        outcome = .available(item.displayVersionString)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        let onLatest = reason.map { $0.int32Value == SPUNoUpdateFoundReason.onLatestVersion.rawValue } ?? false
        outcome = onLatest ? .current : .noCompatibleUpdate
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let result: UpdateProbeOutcome
        if let error, !((error as NSError).domain == SUSparkleErrorDomain && (error as NSError).code == SUError.noUpdateError.rawValue) {
            result = Self.isOffline(error as NSError) ? .offline : .failed
        } else { result = outcome ?? .noCompatibleUpdate }
        let callback = completion; completion = nil; outcome = nil; callback?(result)
    }
    private static func isOffline(_ error: NSError, depth: Int = 0) -> Bool {
        guard depth < 4 else { return false }
        if error.domain == NSURLErrorDomain {
            return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                    NSURLErrorCannotConnectToHost, NSURLErrorTimedOut].contains(error.code)
        }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { isOffline($0, depth: depth + 1) } ?? false
    }
}
