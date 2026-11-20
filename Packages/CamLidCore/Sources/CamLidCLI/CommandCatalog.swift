import Foundation

/// A flag a command accepts. `value` names what the flag takes; nil marks a switch that takes no value.
public struct FlagSpec: Sendable, Equatable {
    public let name: String
    public let value: String?
    public let summary: String
}

/// One command as agents read it from `camlid commands`. The catalog is the single list of commands: the parser,
/// the flag check in the CLI and in the app, and the listing all read it.
public struct CommandSpec: Sendable, Equatable {
    public let name: String
    public let summary: String
    public let usage: String
    /// Changes CamLid state or a setting. A mutating command is refused while CamLid quits.
    public let mutates: Bool
    /// Needs the running app. Without it the command reports appUnavailable.
    public let needsApp: Bool
    /// Positional arguments in order. "<x>" is required; "[x]" is optional.
    public let positionals: [String]
    public let flags: [FlagSpec]
    /// A switch that a destructive command requires before it runs.
    public let confirm: String?
    /// Keys a successful reply carries, besides schemaVersion, command and accepted.
    public let results: [String]
    /// Refusal reasons the command can return. Each one is explained by `camlid commands` and by the reply's hint.
    public let refusals: [String]
    /// The arguments belong to another program (`camlid run -- command`), so flags are not checked.
    public let passthrough: Bool
}

public enum CommandCatalog {
    /// Accepted by every command. The output is always JSON, so the switch changes nothing.
    public static let globalFlags: Set<String> = ["json"]

    /// The settings `config set` writes, by their names in a settings file. Anything else is refused before it is sent.
    public static let settingKeys: Set<String> = [
        "mode", "closedLidOptIn", "completionDelayMinutes", "waitRetentionMinutes", "batteryFloorPercent", "chargingOnly",
        "batteryModeAllowed", "batteryEntryPercent", "batteryCapMinutes", "runCapMinutes", "timerMinutes", "allowDisplaySleep",
        "cpuStopEnabled", "adapterEnrollment", "orcaMetadataConsent", "notificationCategories", "lifetimeRules",
        "launchAtLogin", "powerMode",
    ]

    public static let all: [CommandSpec] = [
        spec("status", "Show the app's state: mode, session, readiness, agents, updates, language, music, audio hold, skill and welcome.",
             "camlid status [--json]",
             results: ["mode", "configuredMode", "effectiveState", "activeSessionMode", "session", "protection", "keepAwake", "health",
                       "tasks", "agentDetection", "updates", "version", "language", "music", "audioHold", "skill", "welcome", "revision",
                       "reasonCodes"],
             refusals: ["appUnavailable"]),
        spec("commands", "List every command with its usage, flags, results and refusal reasons. Start here.",
             "camlid commands", needsApp: false, results: ["exitCodes", "commands"]),
        spec("version", "Show the CLI, app and bundled helper versions.", "camlid version",
             needsApp: false, results: ["cli", "app", "helper"]),
        spec("start", "Start a session. Auto runs while the chosen agents work. Timed runs for --duration. Asking for the session that already runs changes nothing. Replies carry outcome: started, alreadyRunning, timerChanged or replaced.",
             "camlid start [--mode auto|timed] [--duration 45m|2h|infinite] [--replace] [--save-mode] [--closed-lid]",
             mutates: true,
             flags: [flag("mode", "auto|timed", "Auto (default) or Timed. Manual is read as Timed."),
                     flag("duration", "45m|2h|infinite", "Timed only: whole minutes from 5 to 480, or infinite. Units are required."),
                     flag("replace", nil, "Switch a running session: end one of another mode, or change the timer of a running Timed session."),
                     flag("save-mode", nil, "Also save --mode as the next session mode, once the start passes its checks."),
                     flag("closed-lid", nil, "Also keep the Mac awake with the lid closed. Needs Keep awake with the lid closed on, and a permitted helper."),
                     flag("closedLid", nil, "Same as --closed-lid.")],
             results: ["accepted", "changed", "outcome", "mode", "effectiveState", "durationSeconds", "capApplied",
                       "replacedSessionPseudonym", "savedMode", "revision", "closedLid", "closedLidPermit", "powerMode",
                       "powerActuation", "note"],
             refusals: ["invalidMode", "durationNotApplicable", "durationUnitRequired", "invalidDuration", "durationRequired",
                        "sessionAlreadyActive", "closedLidOff", "closedLidNotPermitted", "batteryEntryLow", "batteryUnknown",
                        "notCharging", "powerUnknown", "notStarted", "applicationTerminating", "settingsPending",
                        "recoveryRequired", "revisionConflict", "commitUnconfirmed", "storageUnavailable", "appUnavailable"]),
        spec("stop", "End the running session and release the protection it held.", "camlid stop",
             mutates: true, results: ["released", "cleanupOutcome"], refusals: ["appUnavailable"]),
        spec("quit", "Quit CamLid. It drops the helper connection first, so the helper restores the sleep setting at once.",
             "camlid quit", mutates: true, results: ["accepted", "powerActuation", "cleanupOutcome"], refusals: ["appUnavailable"]),
        spec("session duration", "Change the running Timed session's timer. Only that session changes; the saved default does not.",
             "camlid session duration <45m|2h|infinite> [--expectedRevision N]",
             mutates: true, positionals: ["<duration>"],
             flags: [flag("expectedRevision", "N", "Refuse if settings changed since revision N.")],
             results: ["accepted", "changed", "durationSeconds", "capApplied", "revision"],
             refusals: ["noTimedSession", "durationUnitRequired", "invalidDuration", "invalidRevision", "revisionConflict",
                        "settingsPending", "applicationTerminating", "appUnavailable"]),
        spec("session sleep-delay", "Change how long a running Auto session waits after its work ends. Only that session changes.",
             "camlid session sleep-delay <0m..30m> [--expectedRevision N]",
             mutates: true, positionals: ["<minutes>"],
             flags: [flag("expectedRevision", "N", "Refuse if settings changed since revision N.")],
             results: ["accepted", "changed", "sleepDelayMinutes", "revision"],
             refusals: ["noAutoSession", "durationUnitRequired", "invalidDuration", "invalidRevision", "revisionConflict",
                        "settingsPending", "applicationTerminating", "appUnavailable"]),
        spec("sleep", "Ask whether the Mac may sleep now, and why not if it may not. --dry-run records nothing.",
             "camlid sleep [--dry-run]", flags: [flag("dry-run", nil, "Report only; record no history.")],
             refusals: ["appUnavailable"]),
        spec("simulate", "Run a scenario file against a fake clock, sensors and power. The Mac is not touched.",
             "camlid simulate --scenario <path> [--use-current-config]", needsApp: false,
             flags: [flag("scenario", "path", "The scenario JSON file."),
                     flag("use-current-config", nil, "Use the saved settings instead of the defaults.")]),
        spec("diagnose", "Explain why the Mac is awake: what holds it, which apps, and the reason codes.",
             "camlid diagnose [--json]", refusals: ["appUnavailable"]),
        spec("doctor", "Check permissions, the closed-lid helper, agent integrations and recovery.", "camlid doctor [--json]",
             refusals: ["appUnavailable"]),
        spec("recover", "Restore protection CamLid owns after a crash. Without --apply it only reports what it would do.",
             "camlid recover --owned-only [--dry-run|--apply] [--session <id>]",
             mutates: false, needsApp: false,
             flags: [flag("owned-only", nil, "Required: act only on protection CamLid owns."),
                     flag("ownedOnly", nil, "Same as --owned-only."),
                     flag("apply", nil, "Restore now. Without it the command only reports."),
                     flag("dry-run", nil, "Report only (the default)."),
                     flag("session", "id", "Restrict to one session id.")],
             refusals: ["recoveryRequired", "ownedOnlyRequired"]),
        spec("agents list", "List the agents CamLid can watch: enabled, observed state, working and waiting counts.",
             "camlid agents list [--json]", results: ["agents"], refusals: ["appUnavailable"]),
        spec("agents enable", "Let one agent, or all of them with --all, keep an Auto session awake while it works.",
             "camlid agents enable <provider>|--all", mutates: true, positionals: ["[provider]"],
             flags: [flag("all", nil, "Every agent instead of one.")],
             results: ["accepted", "changed", "enrolled"],
             refusals: ["unknownProvider", "invalidOptions", "revisionConflict", "applicationTerminating", "appUnavailable"]),
        spec("agents disable", "Stop one agent, or all of them with --all, from keeping an Auto session awake.",
             "camlid agents disable <provider>|--all", mutates: true, positionals: ["[provider]"],
             flags: [flag("all", nil, "Every agent instead of one.")],
             results: ["accepted", "changed", "enrolled"],
             refusals: ["unknownProvider", "invalidOptions", "revisionConflict", "applicationTerminating", "appUnavailable"]),
        spec("music list", "List the music sources: whether each is enabled, and whether it is playing now.",
             "camlid music list", results: ["sources"], refusals: ["appUnavailable"]),
        spec("music set", "Turn a music source on or off, so playing music can keep an Auto session awake.",
             "camlid music set <chromium|spotify|apple-music|safari> <on|off>", mutates: true,
             positionals: ["<source>", "<on|off>"], results: ["accepted", "changed", "id", "enabled"],
             refusals: ["unknownSource", "invalidOptions", "applicationTerminating", "appUnavailable"]),
        spec("audio-hold", "Turn the general audio hold on or off. It keeps an Auto session awake while any audio plays (spec 029).",
             "camlid audio-hold <on|off>", mutates: true, positionals: ["<on|off>"],
             results: ["accepted", "changed", "enabled", "holding"], refusals: ["invalidOptions", "applicationTerminating", "appUnavailable"]),
        spec("watch list", "List watched programs with their ids and whether each is enabled.", "camlid watch list [--json]",
             results: ["rules"], refusals: ["appUnavailable"]),
        spec("watch add", "Watch a program so it keeps an Auto session awake while it runs.",
             "camlid watch add (--executable <path> | --bundle-id <id>) [--label <text>]", mutates: true,
             flags: [flag("executable", "path", "The program's executable path."),
                     flag("bundle-id", "id", "The program's bundle identifier."),
                     flag("label", "text", "A name to show in `watch list`.")],
             results: ["accepted", "revision"], refusals: ["invalidOptions", "revisionConflict", "appUnavailable"]),
        spec("watch remove", "Stop watching a program, by the id that `watch list` shows.", "camlid watch remove <id>",
             mutates: true, positionals: ["<id>"], results: ["accepted", "revision"],
             refusals: ["invalidRuleID", "ruleNotFound", "revisionConflict", "appUnavailable"]),
        spec("watch enable", "Turn a watched program on, by its id.", "camlid watch enable <id>", mutates: true,
             positionals: ["<id>"], results: ["accepted", "changed", "id", "enabled", "revision"],
             refusals: ["invalidRuleID", "ruleNotFound", "revisionConflict", "appUnavailable"]),
        spec("watch disable", "Turn a watched program off, by its id. It stays listed.", "camlid watch disable <id>", mutates: true,
             positionals: ["<id>"], results: ["accepted", "changed", "id", "enabled", "revision"],
             refusals: ["invalidRuleID", "ruleNotFound", "revisionConflict", "appUnavailable"]),
        spec("config get", "Read the saved settings and their revision.", "camlid config get [--json]",
             results: ["revision", "mode", "timerMinutes", "runCapMinutes", "completionDelayMinutes", "allowDisplaySleep"],
             refusals: ["appUnavailable"]),
        spec("config validate", "Check a settings file without saving it.", "camlid config validate --file <path>",
             flags: [flag("file", "path", "A JSON file of settings.")], results: ["valid"],
             refusals: ["missingFile", "invalidFile", "invalidConfig"]),
        spec("config set", "Save settings: one as `config set <key> <value>`, or several from a JSON file with --file. --dry-run only checks; --expectedRevision refuses if settings changed.",
             "camlid config set <key> <value> | --file <path> [--dry-run] [--expectedRevision N]", mutates: true,
             positionals: ["[key]", "[value]"],
             flags: [flag("file", "path", "A JSON file of settings, instead of key and value."),
                     flag("dry-run", nil, "Validate and show the difference; save nothing."),
                     flag("expectedRevision", "N", "Refuse if settings changed since revision N.")],
             results: ["accepted", "changed", "revision", "diff"],
             refusals: ["invalidConfig", "invalidFile", "missingFile", "invalidRevision", "revisionConflict", "commitUnconfirmed",
                        "applicationTerminating", "appUnavailable"]),
        spec("logs export", "Export the activity history to a file, redacted: session ids are pseudonyms.",
             "camlid logs export --output <path> [--force]",
             flags: [flag("output", "path", "Where to write the JSON file."),
                     flag("force", nil, "Overwrite an existing file."),
                     flag("overwrite", nil, "Same as --force."),
                     flag("redacted", nil, "Always on; accepted for clarity.")],
             results: ["exported", "redacted", "eventCount"], refusals: ["overwriteRefused", "exportFailed", "appUnavailable"]),
        spec("logs list", "List activity records, newest first, redacted. Pass nextCursor back as --cursor for the next page.",
             "camlid logs list [--limit N] [--cursor T] [--category C] [--reason R] [--query Q] [--include-routine]",
             flags: [flag("limit", "N", "Records per page, 1 to 200. Default 50."),
                     flag("cursor", "token", "The nextCursor of the previous page."),
                     flag("category", "name", "Only this category: stateTransition, safetyStop, grace, capExpiry, recovery, enrollment, configuration."),
                     flag("reason", "code", "Only records that carry this reason code."),
                     flag("query", "text", "Find records whose category, states, reasons or provider contain this text, as the Activity search does."),
                     flag("include-routine", nil, "Include routine sensor updates, which are hidden by default.")],
             results: ["records", "nextCursor", "hiddenRoutineCount"],
             refusals: ["invalidCursor", "invalidFilter", "storageUnavailable", "appUnavailable"]),
        spec("logs delete", "Delete history: one session (--session <sessionPseudonym>) or all of it (--all). Needs --confirm. The receipt says what was removed.",
             "camlid logs delete (--session <sessionPseudonym> | --all) --confirm", mutates: true,
             flags: [flag("session", "sessionPseudonym", "The session to delete, as `logs list` shows it."),
                     flag("all", nil, "Delete every record."),
                     flag("confirm", nil, "Required. Deletion cannot be undone.")],
             confirm: "confirm", results: ["accepted", "receipt"],
             refusals: ["confirmationRequired", "unknownSession", "storageUnavailable", "applicationTerminating", "appUnavailable"]),
        spec("helper status", "Show whether the closed-lid helper is installed and running. Needs no app.", "camlid helper status",
             needsApp: false, flags: [flag("app", "path", "The CamLid app to check, if not the installed one.")],
             results: ["status", "serviceLoaded"]),
        spec("helper install", "Install the closed-lid helper. It needs an administrator: the user runs it with sudo.",
             "sudo camlid helper install [--replace-pins]", mutates: true, needsApp: false,
             flags: [flag("app", "path", "The CamLid app to install from."),
                     flag("replace-pins", nil, "Replace a helper pin from another CamLid install; the old one is kept.")],
             results: ["status"]),
        spec("helper uninstall", "Remove the closed-lid helper. It needs sudo.", "sudo camlid helper uninstall", mutates: true,
             needsApp: false, flags: [flag("app", "path", "The CamLid app whose helper to remove.")]),
        spec("helper trust", "Pin a helper that was installed by hand to this app. It needs sudo.", "sudo camlid helper trust",
             mutates: true, needsApp: false, flags: [flag("app", "path", "The CamLid app to pin the helper to.")]),
        spec("language get", "Read the language CamLid shows, and the language it resolves to.", "camlid language get",
             results: ["language", "resolved"], refusals: ["appUnavailable"]),
        spec("language set", "Set the language CamLid shows: system, english or vietnamese.",
             "camlid language set <system|english|vietnamese>", mutates: true, positionals: ["<language>"],
             results: ["accepted", "changed", "language", "resolved"],
             refusals: ["invalidLanguage", "applicationTerminating", "appUnavailable"]),
        spec("skill status", "Check whether CamLid's skill file for AI agents is installed, and where it is.", "camlid skill status",
             results: ["installed", "path"], refusals: ["appUnavailable"]),
        spec("skill install", "Write CamLid's skill file to ~/.agents/skills/camlid/SKILL.md. A file CamLid did not write is kept unless --replace.",
             "camlid skill install [--replace]", mutates: true,
             flags: [flag("replace", nil, "Overwrite a SKILL.md that CamLid did not write.")],
             results: ["accepted", "changed", "installed", "path"],
             refusals: ["skillConflict", "skillWriteFailed", "qaCopy", "applicationTerminating", "appUnavailable"]),
        spec("skill remove", "Remove the skill file CamLid wrote, if it is unchanged since.", "camlid skill remove", mutates: true,
             results: ["accepted", "changed", "installed", "path"],
             refusals: ["skillModified", "skillWriteFailed", "qaCopy", "applicationTerminating", "appUnavailable"]),
        spec("update status", "Read the update state: phase, reason, version, whether an install is ready, and the daily check.",
             "camlid update status", results: ["phase", "reason", "version", "sessionActive", "recoveryRequired",
                                             "installationAvailable", "automaticChecks"],
             refusals: ["appUnavailable"]),
        spec("update check", "Ask GitHub for the newest release. Returns at once; read `update status` for the answer.",
             "camlid update check", mutates: true, results: ["accepted", "changed", "phase", "reason", "version"],
             refusals: ["networkUnavailable", "recoveryRequired", "qaCopy", "applicationTerminating", "appUnavailable"]),
        spec("update install", "Download, check and install the ready update, then restart CamLid. Returns at once; poll `update status`. A running session needs --stop-session.",
             "camlid update install [--stop-session]", mutates: true,
             flags: [flag("stop-session", nil, "End a running session when the update restarts CamLid.")],
             results: ["accepted", "changed", "phase", "reason", "version"],
             refusals: ["updateNotReady", "sessionActive", "recoveryRequired", "qaCopy", "applicationTerminating", "appUnavailable"]),
        spec("update auto", "Turn the daily update check on or off.", "camlid update auto <on|off>", mutates: true,
             positionals: ["<on|off>"], results: ["accepted", "changed", "automaticChecks"],
             refusals: ["invalidOptions", "applicationTerminating", "appUnavailable"]),
        spec("closed-lid acknowledge-untested", "Allow closed-lid protection on this untested Mac (--confirm), or withdraw that allowance (--revoke).",
             "camlid closed-lid acknowledge-untested (--confirm | --revoke)", mutates: true,
             flags: [flag("confirm", nil, "Allow closed-lid protection on this Mac. Its risks are shown in the refusal hint."),
                     flag("revoke", nil, "Withdraw the allowance.")],
             results: ["accepted", "changed", "acknowledged", "closedLidPermit"],
             refusals: ["confirmationRequired", "macIdentityUnavailable", "applicationTerminating", "appUnavailable"]),
        spec("notifications request", "Ask macOS to allow CamLid's notifications. Returns at once; macOS shows the prompt.",
             "camlid notifications request", mutates: true, results: ["accepted", "changed", "permission"],
             refusals: ["notificationsUnavailable", "notificationsRequestFailed", "applicationTerminating", "appUnavailable"]),
        spec("welcome status", "Check whether the Welcome flow was finished.", "camlid welcome status", results: ["done"],
             refusals: ["appUnavailable"]),
        spec("welcome complete", "Mark the Welcome flow finished, as its Finish button does.", "camlid welcome complete",
             mutates: true, results: ["accepted", "changed", "done"], refusals: ["applicationTerminating", "appUnavailable"]),
        spec("open", "Show a CamLid window: dashboard, settings, settings.general, settings.agents, settings.closed-lid, activity, updates, diagnostics, welcome or about. releases opens the project's releases page in the browser.",
             "camlid open <window>", positionals: ["<window>"], results: ["accepted", "window"],
             refusals: ["unknownWindow", "appUnavailable"]),
        spec("login apply", "Apply the saved launch-at-login setting now.", "camlid login apply", mutates: true,
             results: ["accepted", "changed", "launchAtLogin", "state"], refusals: ["loginItemFailed", "appUnavailable"]),
        spec("run", "Keep the Mac awake while one command runs. The exit code is the command's exit code.",
             "camlid run -- <command> [arguments]", mutates: true, refusals: ["appUnavailable"], passthrough: true),
    ]

    /// Every command name. The parser joins the first word of a multi-word name with the next argument.
    /// The commands the app runs through its `operate` request. Each name is one case of the app's switch, so a name here
    /// that the app did not handle would be refused as unknown, and the app's tests check that they all are handled.
    public static let operated: Set<String> = [
        "session duration", "session sleep-delay", "logs list", "logs delete", "music list", "music set", "audio-hold",
        "language get", "language set", "skill status", "skill install", "skill remove", "update status", "update check",
        "update install", "update auto", "agents enable", "agents disable", "closed-lid acknowledge-untested",
        "notifications request", "welcome status", "welcome complete", "open", "login apply", "version",
    ]

    public static func spec(_ name: String) -> CommandSpec? { all.first { $0.name == name } }

    /// First words of multi-word commands, such as "session" in "session duration".
    public static let groups: Set<String> = Set(all.compactMap { $0.name.contains(" ") ? String($0.name.prefix { $0 != " " }) : nil })

    /// Flags that take no value, so a flag followed by a positional does not swallow it.
    public static let switchFlags: Set<String> = globalFlags.union(all.flatMap { $0.flags.filter { $0.value == nil }.map(\.name) })

    /// The first refusal for these options, or nil. Checks flags the command does not take, missing or extra arguments, and a
    /// missing confirmation switch. Command-specific rules (such as one of --session or --all) are checked by the handler.
    public static func check(_ name: String, _ options: CLIOptions) -> CLIResult? {
        guard let spec = spec(name), !spec.passthrough else { return nil }
        let allowed = Set(spec.flags.map(\.name)).union(globalFlags)
        if let unknown = options.flags.keys.sorted().first(where: { !allowed.contains($0) }) {
            let takes = allowed.sorted().map { "--" + $0 }.joined(separator: ", ")
            return CLIReply.refused(name, reason: "unknownOption", detail: unknown,
                hint: "`camlid \(name)` takes \(takes). Usage: \(spec.usage)")
        }
        let required = spec.positionals.filter { !$0.hasPrefix("[") }.count
        if options.positionals.count < required || options.positionals.count > spec.positionals.count {
            return CLIReply.refused(name, reason: "invalidOptions", detail: "arguments", hint: "Usage: \(spec.usage)")
        }
        if let confirm = spec.confirm, options.flags[confirm] == nil {
            return CLIReply.refused(name, reason: "confirmationRequired", hint: "Run it again with --\(confirm). Usage: \(spec.usage)")
        }
        return nil
    }

    /// The listing `camlid commands` prints.
    public static func listing() -> CLIResult {
        CLIReply.read("commands", [
            "exitCodes": ["0": "ok", "2": "the input is invalid, or a rule the caller can fix refused it",
                          "3": "the state of the Mac or the app refused it", "4": "the app or helper is unavailable; retry later",
                          "5": "recovery is needed, or the outcome is not known yet"],
            "globalFlags": globalFlags.sorted().map { "--" + $0 },
            "commands": all.map(description),
        ])
    }

    static func description(_ spec: CommandSpec) -> [String: Any] {
        [
            "name": spec.name,
            "summary": spec.summary,
            "usage": spec.usage,
            "mutates": spec.mutates,
            "needsApp": spec.needsApp,
            "positionals": spec.positionals,
            "flags": spec.flags.map { flag -> [String: Any] in
                ["name": flag.name, "value": flag.value ?? NSNull(), "summary": flag.summary]
            },
            "confirm": spec.confirm.map { "--" + $0 } ?? NSNull(),
            "results": spec.results,
            "refusals": spec.refusals,
        ]
    }

    private static func spec(_ name: String, _ summary: String, _ usage: String, mutates: Bool = false, needsApp: Bool = true,
                             positionals: [String] = [], flags: [FlagSpec] = [], confirm: String? = nil,
                             results: [String] = [], refusals: [String] = [], passthrough: Bool = false) -> CommandSpec {
        CommandSpec(name: name, summary: summary, usage: usage, mutates: mutates, needsApp: needsApp, positionals: positionals,
                    flags: flags, confirm: confirm, results: results, refusals: refusals, passthrough: passthrough)
    }

    private static func flag(_ name: String, _ value: String?, _ summary: String) -> FlagSpec {
        FlagSpec(name: name, value: value, summary: summary)
    }
}
