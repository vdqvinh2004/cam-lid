/// The helper's backend is chosen only by an explicit argument; no argument is refused so an
/// incomplete launchd plist can never silently select the global-policy backend.
public enum HelperLaunchMode: Equatable, Sendable {
    case standard, lidSpecific, bestEffortLid, recovery, release

    public static let standardArgument = "--standard-v1"
    public static let lidSpecificArgument = "--lid-specific-v1"
    public static let bestEffortLidArgument = "--lid-specific-best-effort-v1"
    public static let recoveryArgument = "--recover-v1"
    /// Restores an owned acknowledged enable immediately (used by uninstall).
    public static let releaseArgument = "--release-v1"

    public init?(arguments: [String]) {
        switch arguments {
        case [Self.standardArgument]: self = .standard
        case [Self.lidSpecificArgument]: self = .lidSpecific
        case [Self.bestEffortLidArgument]: self = .bestEffortLid
        case [Self.recoveryArgument]: self = .recovery
        case [Self.releaseArgument]: self = .release
        default: return nil
        }
    }
}
