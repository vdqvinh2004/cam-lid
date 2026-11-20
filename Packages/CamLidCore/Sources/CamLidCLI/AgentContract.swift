import Foundation
import CamLidCore

/// Advice for one refusal reason. Agents act on these fields instead of parsing text.
public struct RefusalInfo: Sendable, Equatable {
    /// The exit code a refusal with this reason uses unless its caller passes another.
    public let exit: Int
    /// Whether the same call can succeed later without a change the caller makes.
    public let retryable: Bool
    /// The next step, in plain words an agent can act on.
    public let hint: String
}

/// Every refusal reason the CLI returns, with its exit code, retry advice and next step.
public enum CLIReasons {
    public static let fallback = RefusalInfo(exit: 2, retryable: false,
        hint: "Run `camlid commands` to see every command, its flags and its refusal reasons.")

    public static func info(_ reason: String) -> RefusalInfo { table[reason] ?? fallback }

    public static let table: [String: RefusalInfo] = [
        // The input can be fixed by the caller.
        "unknownCommand": RefusalInfo(exit: 2, retryable: false, hint: "Run `camlid commands` to list the commands."),
        "unknownOption": RefusalInfo(exit: 2, retryable: false, hint: "Use only the flags that `camlid commands` lists for this command."),
        "invalidOptions": RefusalInfo(exit: 2, retryable: false, hint: "Check the arguments against the usage line in `camlid commands`."),
        "missingSubcommand": RefusalInfo(exit: 2, retryable: false, hint: "Name the subcommand; `camlid commands` lists them."),
        "missingFile": RefusalInfo(exit: 2, retryable: false, hint: "Pass --file <path>, or write the setting as `config set <key> <value>`."),
        "invalidFile": RefusalInfo(exit: 2, retryable: false, hint: "The file must be readable JSON with a size under the limit."),
        "invalidConfig": RefusalInfo(exit: 2, retryable: false, hint: "A setting has a wrong type or value. `camlid config get` shows the valid shape."),
        "invalidRevision": RefusalInfo(exit: 2, retryable: false, hint: "Pass --expectedRevision as a whole number from `camlid config get`."),
        "invalidMode": RefusalInfo(exit: 2, retryable: false, hint: "Use --mode auto or --mode timed."),
        "durationUnitRequired": RefusalInfo(exit: 2, retryable: false,
            hint: "Write the duration with a unit: 45m, 2h or infinite. A bare number is refused, so 60 is not read as seconds."),
        "invalidDuration": RefusalInfo(exit: 2, retryable: false,
            hint: "A Timed duration is infinite or whole minutes from 5 to 480, written as 45m or 2h. Zero is written as infinite."),
        "durationRequired": RefusalInfo(exit: 2, retryable: false,
            hint: "Timed needs a duration: --duration 45m, --duration 2h or --duration infinite."),
        "durationNotApplicable": RefusalInfo(exit: 2, retryable: false,
            hint: "Auto has no timer. Use --mode timed with --duration, or drop --duration."),
        "confirmationRequired": RefusalInfo(exit: 2, retryable: true,
            hint: "This changes or deletes data. Run the same command again with the confirmation switch named in the usage line."),
        "revisionConflict": RefusalInfo(exit: 2, retryable: true,
            hint: "Settings changed since you read them. Run `camlid config get`, check the new value, then retry with its revision."),
        "unknownProvider": RefusalInfo(exit: 2, retryable: false, hint: "Use a provider id from `camlid agents list`."),
        "unknownSource": RefusalInfo(exit: 2, retryable: false, hint: "Use chromium, spotify, apple-music or safari."),
        "ruleNotFound": RefusalInfo(exit: 2, retryable: false, hint: "Find the rule id with `camlid watch list`."),
        "invalidRuleID": RefusalInfo(exit: 2, retryable: false, hint: "Pass the rule id that `camlid watch list` shows: a UUID."),
        "invalidRule": RefusalInfo(exit: 2, retryable: false,
            hint: "The program cannot be watched as given. Check the executable path or the bundle id, and that the rule is not a duplicate."),
        "unknownSetting": RefusalInfo(exit: 2, retryable: false,
            hint: "Use a setting name from `camlid config get`, for example `camlid config set runCapMinutes 120`."),
        "overwriteRefused": RefusalInfo(exit: 2, retryable: false,
            hint: "The file already exists. Pass --force to replace it, or choose another path."),
        "exportFailed": RefusalInfo(exit: 4, retryable: true, hint: "The export could not be written. Check the path and retry."),
        "ownedOnlyRequired": RefusalInfo(exit: 2, retryable: false,
            hint: "Recovery acts only on protection CamLid owns. Pass --owned-only."),
        "missingOutput": RefusalInfo(exit: 2, retryable: false, hint: "Pass --output <path> for the file to write."),
        "executableNotFound": RefusalInfo(exit: 2, retryable: false, hint: "No executable exists at that path. Check the path with `ls`."),
        "applicationNotInstalled": RefusalInfo(exit: 2, retryable: false,
            hint: "No installed app has that bundle id. Check it with `mdls -name kMDItemCFBundleIdentifier <app>`."),
        "unknownSession": RefusalInfo(exit: 2, retryable: false, hint: "Use a sessionPseudonym from `camlid logs list`."),
        "unknownWindow": RefusalInfo(exit: 2, retryable: false, hint: "Use one of the window names in the usage line of `camlid open`."),
        "invalidLanguage": RefusalInfo(exit: 2, retryable: false, hint: "Use system, english or vietnamese."),
        "invalidCursor": RefusalInfo(exit: 2, retryable: false, hint: "Start again without --cursor, then use the nextCursor of the new reply."),
        "invalidFilter": RefusalInfo(exit: 2, retryable: false, hint: "Use a category from `camlid logs list --category` or a reason code from a record."),
        "skillConflict": RefusalInfo(exit: 2, retryable: false,
            hint: "A SKILL.md that CamLid did not write is already there. Add --replace to overwrite it."),
        "skillModified": RefusalInfo(exit: 2, retryable: false,
            hint: "The installed skill file was edited, so CamLid kept it. Delete it yourself, or install again with --replace."),
        // The state of the Mac or the app refuses the call.
        "sessionAlreadyActive": RefusalInfo(exit: 3, retryable: false,
            hint: "A session of another mode or duration is running. Add --replace to switch, `camlid session duration` to change its timer, or `camlid stop` first."),
        "noTimedSession": RefusalInfo(exit: 3, retryable: false,
            hint: "No Timed session is running. Start one with `camlid start --mode timed --duration 45m`."),
        "noAutoSession": RefusalInfo(exit: 3, retryable: false,
            hint: "No Auto session is running. Start one with `camlid start --mode auto`."),
        "modeOff": RefusalInfo(exit: 3, retryable: false, hint: "The saved mode is off. Start with --mode auto or --mode timed."),
        "closedLidNotPermitted": RefusalInfo(exit: 3, retryable: false,
            hint: "Closed-lid protection is not permitted on this Mac yet. Run `camlid doctor` and `camlid helper status`."),
        "batteryEntryLow": RefusalInfo(exit: 3, retryable: true,
            hint: "The battery is below the start level. Connect the charger, then retry."),
        "batteryUnknown": RefusalInfo(exit: 3, retryable: true, hint: "The battery reading is unavailable. Retry once `camlid status` shows readings."),
        "notCharging": RefusalInfo(exit: 3, retryable: true,
            hint: "Charger-only mode is on and the Mac is not charging. Connect the charger, or change the setting with `camlid config set chargingOnly false`."),
        "updateNotReady": RefusalInfo(exit: 3, retryable: true,
            hint: "No update is ready to install. Run `camlid update check`, then read `camlid update status` until installationAvailable is true."),
        "sessionActive": RefusalInfo(exit: 3, retryable: true,
            hint: "A session is running. Add --stop-session to end it before the update restarts CamLid."),
        "notificationsUnavailable": RefusalInfo(exit: 3, retryable: false, hint: "Notifications are not available in this build of CamLid."),
        "qaCopy": RefusalInfo(exit: 3, retryable: false,
            hint: "This is a QA copy of CamLid. It cannot change the installed app or the shared skill file. Use the installed app's camlid."),
        "applicationTerminating": RefusalInfo(exit: 3, retryable: true, hint: "CamLid is quitting. Open CamLid again, then retry."),
        // The app or helper cannot be reached, or cannot finish now.
        "appUnavailable": RefusalInfo(exit: 4, retryable: true,
            hint: "CamLid is not running or cannot be reached. Ask the user to open CamLid, then retry. Do not launch it yourself."),
        "storageUnavailable": RefusalInfo(exit: 4, retryable: true,
            hint: "CamLid could not read or save its data in time. Retry. Before you retry a deletion, read `camlid logs list` to see what remains."),
        "networkUnavailable": RefusalInfo(exit: 4, retryable: true, hint: "GitHub could not be reached. Retry later; installed CamLid is unchanged."),
        "skillWriteFailed": RefusalInfo(exit: 4, retryable: true, hint: "The skill file could not be written. Check that the home folder is writable, then retry."),
        "loginItemFailed": RefusalInfo(exit: 4, retryable: true,
            hint: "macOS did not change the login item. Ask the user to check Login Items in System Settings."),
        "notificationsRequestFailed": RefusalInfo(exit: 4, retryable: true, hint: "macOS did not start the notification request. Retry in a moment."),
        "invalidAppReply": RefusalInfo(exit: 4, retryable: true,
            hint: "CamLid answered in an unexpected way. Retry; if it persists, run `camlid doctor`."),
        // Recovery is needed, or the outcome is not known yet.
        "recoveryRequired": RefusalInfo(exit: 5, retryable: false,
            hint: "CamLid must finish recovery first. Run `camlid recover --owned-only --dry-run`, then read `camlid status`."),
        "commitUnconfirmed": RefusalInfo(exit: 5, retryable: true,
            hint: "The change may still apply. Read `camlid config get` before you write again."),
        "powerUnknown": RefusalInfo(exit: 3, retryable: true,
            hint: "The power source is not known yet. Retry once `camlid status` shows the power source."),
        "closedLidOff": RefusalInfo(exit: 3, retryable: false,
            hint: "Keep awake with the lid closed is off in Settings. Turn it on with `camlid config set closedLidOptIn true` once `camlid doctor` shows the helper ready, or drop --closed-lid."),
        "macIdentityUnavailable": RefusalInfo(exit: 3, retryable: false,
            hint: "CamLid cannot read this Mac's model and macOS build, so it cannot record the untested-Mac acknowledgement. Ask the user to record it in Settings › Closed Lid."),
        "settingsPending": RefusalInfo(exit: 3, retryable: true,
            hint: "Settings are still being saved. Wait a moment, then read `camlid config get` and retry."),
        "notStarted": RefusalInfo(exit: 3, retryable: true, hint: "CamLid did not start the session. Read `camlid status` for the reason, then retry."),
    ]
}

/// Builds the JSON replies. Each reply has `schemaVersion` and `command`; refusals add `reason`, `retryable` and `hint`.
public enum CLIReply {
    /// A refusal. The exit code defaults to the reason's entry in `CLIReasons`.
    public static func refused(_ command: String, reason: String, exit: Int? = nil, detail: String? = nil,
                               hint: String? = nil, extra: [String: Any] = [:]) -> CLIResult {
        let info = CLIReasons.info(reason)
        var object = extra
        object["accepted"] = false
        object["reason"] = reason
        object["retryable"] = info.retryable
        object["hint"] = hint ?? info.hint
        if let detail { object["detail"] = detail }
        return encode(command, object, exit: exit ?? info.exit)
    }

    /// A successful write. `changed` is false when the setting or state already had the requested value.
    public static func done(_ command: String, changed: Bool, _ fields: [String: Any] = [:]) -> CLIResult {
        var object = fields
        object["accepted"] = true
        object["changed"] = changed
        return encode(command, object, exit: 0)
    }

    /// A read. It has no `accepted` key.
    public static func read(_ command: String, _ fields: [String: Any], exit: Int = 0) -> CLIResult {
        encode(command, fields, exit: exit)
    }

    static func encode(_ command: String, _ fields: [String: Any], exit: Int) -> CLIResult {
        var object = fields
        object["schemaVersion"] = 1
        object["command"] = command
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return CLIResult(json: String(decoding: data, as: UTF8.self), exitCode: exit)
    }
}

/// The timer limits. The CLI and the app read the same numbers, so a value refused here is refused there too.
public enum TimerRules {
    /// Whole minutes a Timed session may run. Zero is Infinite and is not in this range.
    public static let minutes = 5...480
    /// Minutes an Auto session waits after its work ends.
    public static let sleepDelay = 0...30

    public static func isTimer(_ value: Int) -> Bool { value == 0 || minutes.contains(value) }
}

/// A duration as written on the command line.
public enum DurationArg: Sendable, Equatable {
    case minutes(Int)
    case infinite
}

/// Reads `45m`, `2h` or `infinite`. Units are required: a bare number is refused, so `60` is never read as seconds.
public enum DurationText {
    public enum Failure: Error, Sendable, Equatable {
        case unitRequired
        case invalid
    }

    public static func parse(_ raw: String, allowInfinite: Bool) -> Result<DurationArg, Failure> {
        if raw == "infinite" { return allowInfinite ? .success(.infinite) : .failure(.invalid) }
        if !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) { return .failure(.unitRequired) }
        guard let unit = raw.last, unit == "m" || unit == "h" else { return .failure(.invalid) }
        let digits = String(raw.dropLast())
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits) else {
            return .failure(.invalid)
        }
        return .success(.minutes(unit == "h" ? value * 60 : value))
    }
}

/// `camlid start`, read and checked the same way on the command line and in the app.
public struct StartRequest: Sendable, Equatable {
    public let mode: RequestedMode
    /// nil when no duration was given. Zero means Infinite.
    public let minutes: Int?
    public let replace: Bool
    public let saveMode: Bool
    public let closedLid: Bool

    /// The request, or the refusal to return as it is.
    public static func parse(_ options: CLIOptions) -> StartParse {
        let raw = options.flags["mode"] ?? "auto"
        guard let parsed = RequestedMode(rawValue: raw), parsed != .off else {
            return .refused(CLIReply.refused("start", reason: "invalidMode", detail: raw))
        }
        // The Dashboard shows Manual as Timed, so the command reads it as Timed too.
        let mode: RequestedMode = parsed == .manual ? .timed : parsed
        var minutes: Int?
        if let text = options.flags["duration"] {
            guard mode != .auto else { return .refused(CLIReply.refused("start", reason: "durationNotApplicable", detail: text)) }
            switch DurationText.parse(text, allowInfinite: true) {
            case .failure(.unitRequired):
                return .refused(CLIReply.refused("start", reason: "durationUnitRequired", detail: text))
            case .failure(.invalid):
                return .refused(CLIReply.refused("start", reason: "invalidDuration", detail: text))
            case .success(.infinite):
                minutes = 0
            case .success(.minutes(let value)):
                guard TimerRules.minutes.contains(value) else {
                    return .refused(CLIReply.refused("start", reason: "invalidDuration", detail: text))
                }
                minutes = value
            }
        }
        if mode == .timed, minutes == nil {
            return .refused(CLIReply.refused("start", reason: "durationRequired"))
        }
        return .accepted(StartRequest(mode: mode, minutes: minutes,
            replace: options.flags["replace"] != nil,
            saveMode: options.flags["save-mode"] != nil,
            closedLid: options.flags["closed-lid"] != nil || options.flags["closedLid"] != nil))
    }
}

/// The outcome of reading a start request.
public enum StartParse: Sendable {
    case accepted(StartRequest)
    case refused(CLIResult)
}

/// One app-side operation: the catalog name and the flags and positionals it was given.
public struct OperateRequest: Codable, Sendable, Equatable {
    public let name: String
    public let options: CLIOptions

    public init(name: String, options: CLIOptions) {
        self.name = name
        self.options = options
    }
}

/// The version and build of the CamLid app that contains this tool. The tool lives in CamLid.app/Contents/Helpers.
public enum BuildInfo {
    public static func enclosingApp(executable: URL?) -> (version: String?, build: String?) {
        guard let executable else { return (nil, nil) }
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let bundle = Bundle(url: app) else { return (nil, nil) }
        return (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }
}
