/// Restoration-before-sleep gate and sleep-request outcomes.
/// T020: sleep follows verified restoration; requested/observed/blocked stay distinct.
/// Lease expiration alone never counts as verified restoration.
public enum RestoreState: String, Sendable, Codable, CaseIterable {
    case pending, verified, failed, conflict, unknown
}

public enum SleepDecision: Sendable, Equatable {
    case request
    case hold(reason: String)
    case blocked(reason: String)
}

public enum PowerController {
    public static func restorationRequired(_ restore: RestoreState) -> Bool {
        restore != .verified
    }

    /// Decides a closed-lid sleep request. Lid unknown blocks (lid is a sensor
    /// input, never assumed). Unverified restoration holds the request; failed
    /// or conflicted restoration blocks it until recovery resolves.
    public static func sleepRequest(lidState: LidState, restore: RestoreState) -> SleepDecision {
        guard lidState != .unknown else { return .blocked(reason: "blockerUnknown") }
        switch restore {
        case .verified:
            return .request
        case .pending, .unknown:
            return .hold(reason: "restorationPending")
        case .failed:
            return .blocked(reason: "restorationFailed")
        case .conflict:
            return .blocked(reason: "restorationConflict")
        }
    }
}

/// Backend capability interface. The concrete backend is chosen by M1 (T015–T018
/// stay blocked until then); this protocol keeps the controller honest about that.
public protocol PowerBackend: Sendable {
    var backendName: String { get }
    var requiresHelper: Bool { get }
    func acquire() throws -> String
    func releaseLease() throws
    func verifyRestoration() throws -> RestoreState
}
