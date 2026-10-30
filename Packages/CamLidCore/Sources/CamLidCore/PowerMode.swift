/// Closed-lid backend choice. Both modes share one helper label and one Mach service, so only one mode's
/// daemon can be installed at a time; switching therefore means reinstalling with the other argument.
public enum PowerMode: String, Codable, Sendable, CaseIterable {
    case standard
    case strict

    public var title: String { self == .standard ? "Standard" : "Strict (experimental)" }

    /// Strict keeps the frozen lid-only mechanism and its one-use admission; it is opt-in and unqualified.
    public var isExperimental: Bool { self == .strict }

    public var helperArgument: String {
        switch self {
        case .standard: "--standard-v1"
        case .strict: "--lid-specific-best-effort-v1"
        }
    }

    /// Plain statement shown wherever the mode is chosen (spec 014 FR-012).
    public var disclosure: String {
        switch self {
        case .standard:
            "Standard changes the Mac's global sleep setting while a session runs and restores it when the session ends, "
            + "the battery or temperature guard trips, or CamLid stops responding. It is less strict than Strict mode."
        case .strict:
            "Experimental. Strict uses a narrower lid-only control with one-use approval for each session, is limited to short "
            + "attended sessions on AC power, and is not qualified. It is unavailable until its helper has been admitted."
        }
    }
}

public enum PowerModeSwitchDecision: Equatable, Sendable {
    case allowed
    case refused(reason: String)
}

public enum PowerModeSwitch {
    /// A switch is refused while the active helper holds a lease or has an unresolved journal entry,
    /// and when the target is unavailable. Switching to the current mode is a no-op that is allowed.
    public static func decide(from current: PowerMode, to target: PowerMode, leaseActive: Bool,
                              journalUnresolved: Bool, targetAvailable: Bool) -> PowerModeSwitchDecision {
        guard current != target else { return .allowed }
        if leaseActive { return .refused(reason: "leaseActive") }
        if journalUnresolved { return .refused(reason: "journalUnresolved") }
        if !targetAvailable { return .refused(reason: "modeUnavailable") }
        return .allowed
    }
}
