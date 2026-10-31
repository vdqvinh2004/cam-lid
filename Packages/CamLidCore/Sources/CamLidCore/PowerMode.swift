/// Closed-lid mechanism. One helper serves both (ADR 0003); each session's lease names the mechanism, and the
/// choice may change only while no session runs.
public enum PowerMode: String, Codable, Sendable, CaseIterable {
    case standard
    case strict

    public var title: String { self == .standard ? "Standard" : "Strict (experimental)" }

    /// Strict uses an undocumented kernel interface; it is opt-in and qualified per Mac separately (ADR 0003).
    public var isExperimental: Bool { self == .strict }

    /// One line under the mode choice; `disclosure` is the full statement (shown as help).
    public var summary: String {
        switch self {
        case .standard: "Turns off sleep while a session runs and restores it afterwards."
        case .strict: "Experimental: blocks only lid-close sleep; a restart always clears it."
        }
    }

    /// Plain statement shown wherever the mode is chosen (spec 014 FR-012).
    public var disclosure: String {
        switch self {
        case .standard:
            "Standard changes the Mac's global sleep setting while a session runs and restores it when the session ends, "
            + "the battery or temperature guard trips, or CamLid stops responding. It is less strict than Strict mode."
        case .strict:
            "Experimental. Strict blocks only lid-close sleep and changes no saved setting: a restart clears it, and ending "
            + "a session with the lid closed sleeps the Mac. macOS can end it early, for example when "
            + "a display is connected; the session then stops and says so."
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
