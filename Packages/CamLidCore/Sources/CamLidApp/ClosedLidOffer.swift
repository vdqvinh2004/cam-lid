/// What the closed-lid option offers next (spec 027). The Dashboard and Settings both ask this one rule, so they agree.
enum ClosedLidOffer: Equatable {
    /// Nothing to offer: the option is on and the helper is ready.
    case none
    /// The helper is missing. Settings disables the option until it is installed.
    case installHelper
    /// The helper must be reinstalled or repaired before the option can work.
    case reinstallHelper
    /// The helper is ready and this Mac may use closed lid: one click turns the option on.
    case turnOn
    /// This Mac cannot use closed lid (untested, or Strict is not tested). Settings › Closed Lid says what is missing.
    case openSettings

    /// `helperState` is the helper's state string (`installed`, `notInstalled`, …). `macAllowed` says whether this Mac may use closed lid.
    static func offer(helperState: String, optionOn: Bool, macAllowed: Bool) -> ClosedLidOffer {
        guard macAllowed else { return .openSettings }
        switch helperState {
        case "installed": return optionOn ? .none : .turnOn
        case "notInstalled": return .installHelper
        case "needsReauthorization", "needsHelperUpdate", "installedNotLoaded": return .reinstallHelper
        default: return .openSettings
        }
    }

    /// Settings disables the option only while it is off and the helper is not ready, so an option that is on can always be turned off.
    static func optionEnabled(helperState: String, optionOn: Bool) -> Bool {
        optionOn || helperState == "installed"
    }
}
