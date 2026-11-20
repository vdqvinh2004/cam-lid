import AppKit
import Foundation
import CamLidCore

/// CLI command implementations per contracts/cli.md (T023).
/// Every command returns `(json: String, exitCode: Int)`; every JSON payload
/// carries `schemaVersion: 1`. Exit codes: 0 ok, 2 input invalid, 3
/// policy/capability denied, 4 app/helper unavailable, 5 recovery needed. The
/// Legacy agent event/bridge/run commands refuse before IO or execution.
/// Reads never launch protection or mutate power; `simulate` and all
/// dry-runs are pure.
public struct CLIResult: Sendable, Equatable, Codable {
    public var json: String
    public var exitCode: Int
    public init(json: String, exitCode: Int) { self.json = json; self.exitCode = exitCode }
}

public struct CLIOptions: Sendable, Equatable, Codable {
    /// `--key value` / `--key=value` / bare `--flag` (stored as `"true"`).
    public var flags: [String: String]
    public var positionals: [String]
    public init(flags: [String: String] = [:], positionals: [String] = []) {
        self.flags = flags
        self.positionals = positionals
    }
}

/// Mutable CLI runtime. `files` is a virtual file map (path -> content) so
/// `--file`/`--output` stay testable without host filesystem access;
/// `nowMonotonic` pins fake time for deterministic policy evaluation.
///
/// F03 plumbing: when `fileReader` / `stdinReader` / `fileWriter` are present
/// they take precedence over the virtual map and actually touch disk/stdin.
/// The executable wires disk implementations; unit tests use the virtual map
/// or `InMemoryFileStore` fakes. `historyStore == nil` means no wired history
/// (honest unavailable, exit 4); a non-nil store (even empty in-memory) is a
/// real wired store whose export is honest.
public struct CommandContext: Sendable {
    public var config: Configuration
    public var revision: Int
    public var session: ProtectionSession?
    public var health: HealthSnapshot?
    public var channel: (any IPCChannel)?
    public var journal: RecoveryJournal
    public var files: [String: String]
    public var stdinData: Data?
    public var ownerIdentity: String
    public var nowMonotonic: Double
    public var fileReader: (any CLIFileReader)?
    public var stdinReader: (any CLIStdinReader)?
    public var fileWriter: (any CLIAtomicWriter)?
    public var historyStore: (any HistoryStorage)?
    public var recoveryService: (any RecoveryService)?
    /// The saved settings file of the copy this tool belongs to (`StateLocations.settingsURL`). Nil reads nothing.
    public var settingsURL: URL?

    public init(
        channel: (any IPCChannel)? = nil, ownerIdentity: String = "local-user",
        nowMonotonic: Double = 0, files: [String: String] = [:], stdinData: Data? = nil,
        fileReader: (any CLIFileReader)? = nil,
        stdinReader: (any CLIStdinReader)? = nil,
        fileWriter: (any CLIAtomicWriter)? = nil,
        historyStore: (any HistoryStorage)? = InMemoryHistoryStorage(),
        recoveryService: (any RecoveryService)? = nil
    ) {
        // Library defaults are valid by construction; cannot fail.
        self.config = try! Configuration()
        self.revision = 1
        self.session = nil
        self.health = nil
        self.channel = channel
        self.journal = RecoveryJournal()
        self.files = files
        self.stdinData = stdinData
        self.ownerIdentity = ownerIdentity
        self.nowMonotonic = nowMonotonic
        self.fileReader = fileReader
        self.stdinReader = stdinReader
        self.fileWriter = fileWriter
        self.historyStore = historyStore
        self.recoveryService = recoveryService
    }
}

public enum Commands {
    // MARK: - Entry points

    /// Parses argv (WITHOUT the program name) into `(command, options)`.
    /// Compound subcommands fold: `agents list`, `config get|validate|set`,
    /// `logs export`, and `watch list|add|remove`. `--` stops flag parsing; the rest is positional (used by
    /// `run -- command args...`).
    public static func parse(argv: [String]) -> (command: String, options: CLIOptions) {
        guard !argv.isEmpty else { return ("", CLIOptions()) }
        var args = argv
        var name = args.removeFirst()
        if CommandCatalog.groups.contains(name),
           let next = args.first, !next.hasPrefix("-") {
            name += " " + args.removeFirst()
        }
        var flags: [String: String] = [:]
        var positionals: [String] = []
        var i = 0
        while i < args.count {
            let token = args[i]
            if token == "--" {
                positionals.append(contentsOf: args[(i + 1)...])
                break
            } else if token.hasPrefix("--") {
                let key = String(token.dropFirst(2))
                if let eq = key.firstIndex(of: "=") {
                    flags[String(key[..<eq])] = String(key[key.index(after: eq)...])
                } else if CommandCatalog.switchFlags.contains(key) {
                    flags[key] = "true"
                } else if i + 1 < args.count, !args[i + 1].hasPrefix("-"), args[i + 1] != "--" {
                    flags[key] = args[i + 1]
                    i += 1
                } else {
                    flags[key] = "true"
                }
            } else {
                positionals.append(token)
            }
            i += 1
        }
        return (name, CLIOptions(flags: flags, positionals: positionals))
    }

    /// Main entry: `argv` excludes the program name. A nil channel means the
    /// app is unreachable; app-dependent commands then report exit 4.
    public static func run(argv: [String], channel: (any IPCChannel)?) -> CLIResult {
        let (name, options) = parse(argv: argv)
        var context = CommandContext(channel: channel)
        return dispatch(name, options: options, context: &context)
    }

    /// Real executable entry (F03): wires disk/stdin readers and an atomic
    /// disk writer with no history store (unavailable until M4 lands), so
    /// config/simulate read real files, legacy integration commands refuse, and logs
    /// export honestly reports unavailable instead of inventing success.
    public static func runWithRealIO(argv: [String], channel: (any IPCChannel)?, settingsURL: URL? = nil,
                                     mayChangeHelper: Bool = false) -> CLIResult {
        if argv.first == "run" { return CommandRun.execute(arguments: Array(argv.dropFirst()), channel: channel) }
        let (parsed, options) = parse(argv: argv)
        // No arguments at all print the listing, so an agent that runs `camlid` learns the interface from the reply.
        let name = argv.isEmpty ? "commands" : parsed
        if name == "commands" || name == "help" { return CommandCatalog.listing() }
        if let refusal = CommandCatalog.check(name, options) { return refusal }
        // Only the installed app changes the shared helper; a QA copy's tool never does (see `StateLocations`).
        if !mayChangeHelper, name.hasPrefix("helper"), name != "helper status" { return fail(2, command: name, reason: "qaCopy") }
        var context = CommandContext(
            channel: channel,
            fileReader: DiskFileReader(),
            stdinReader: StandardInputReader(),
            fileWriter: DiskAtomicWriter(),
            historyStore: nil)
        context.settingsURL = settingsURL
        if name.hasPrefix("watch ") {
            guard let channel else { return fail(4, command: name, reason: "appUnavailable") }
            return watchWithRealIO(name: name, options: options, channel: channel)
        }
        let remote: [String: AllowlistedCommand] = [
            "status": .status, "agents": .agentsList, "agents list": .agentsList,
            "config": .configGet, "config get": .configGet,
            "config set": .configSet, "start": .start, "stop": .stop, "quit": .quit, "doctor": .doctor,
        ]
        if let command = remote[name] {
            guard let channel else { return fail(4, command: name, reason: "appUnavailable") }
            var transmitted = options
            if command == .configSet {
                if let path = options.flags["file"] {
                    do {
                        let bytes = try DiskFileReader().readFile(atPath: path)
                        guard let content = String(data: bytes, encoding: .utf8) else { return fail(2, command: name, reason: "invalidFile") }
                        transmitted.flags["patchJSON"] = content
                    } catch { return fail(2, command: name, reason: "invalidFile") }
                } else {
                    // `config set <key> <value>`: one setting, checked against the known keys before anything is sent.
                    guard options.positionals.count == 2 else { return fail(2, command: name, reason: "missingFile") }
                    guard let content = shorthandPatch(key: options.positionals[0], value: options.positionals[1]) else {
                        return fail(2, command: name, reason: "unknownSetting", detail: options.positionals[0])
                    }
                    transmitted.flags["patchJSON"] = content
                }
                transmitted.flags["file"] = "remote-patch"
            }
            do {
                let payload = try JSONEncoder().encode(transmitted)
                return try JSONDecoder().decode(CLIResult.self, from: channel.send(command: command, payload: payload))
            } catch let error as IPCError { return ipcFail(error, command: name) }
            catch { return fail(4, command: name, reason: "invalidAppReply") }
        }
        if name == "logs" || name == "logs export" {
            guard let channel else { return fail(4, command: name, reason: "appUnavailable") }
            do {
                let bytes = try channel.send(command: .logsExport, payload: Data())
                let records = try JSONDecoder().decode([RedactedTransition].self, from: bytes)
                guard let output = options.flags["output"] else { return fail(2, command: name, reason: "missingOutput") }
                let writer = DiskAtomicWriter()
                if writer.fileExists(atPath: output), options.flags["force"] == nil, options.flags["overwrite"] == nil {
                    return fail(2, command: name, reason: "overwriteRefused")
                }
                try writer.writeAtomically(bytes, toPath: output, overwrite: options.flags["force"] != nil || options.flags["overwrite"] != nil)
                return cliJSON(0, ["command": "logsExport", "exported": true, "redacted": true, "eventCount": records.count])
            } catch let error as IPCError { return ipcFail(error, command: name) }
            catch CLIFileWriteError.overwriteRefused { return fail(2, command: name, reason: "overwriteRefused") }
            catch { return fail(2, command: name, reason: "exportFailed") }
        }
        if name == "version" { return versionWithRealIO(channel: channel) }
        if CommandCatalog.operated.contains(name) {
            guard let channel else { return CLIReply.refused(name, reason: "appUnavailable") }
            return operateWithRealIO(name: name, options: options, channel: channel)
        }
        return dispatch(name, options: options, context: &context)
    }

    /// Sends one app-side operation (`session duration`, `logs list`, and the rest of the catalog) to the app.
    static func operateWithRealIO(name: String, options: CLIOptions, channel: any IPCChannel) -> CLIResult {
        do {
            let payload = try JSONEncoder().encode(OperateRequest(name: name, options: options))
            return try JSONDecoder().decode(CLIResult.self, from: channel.send(command: .operate, payload: payload))
        } catch let error as IPCError {
            return ipcFail(error, command: name)
        } catch {
            return CLIReply.refused(name, reason: "invalidAppReply")
        }
    }

    /// `camlid version`: this tool's build always, and the running app's and the bundled helper's when the app answers.
    static func versionWithRealIO(channel: (any IPCChannel)?) -> CLIResult {
        let tool = BuildInfo.enclosingApp(executable: Bundle.main.executableURL)
        var app: Any = NSNull()
        var helper: Any = NSNull()
        if let channel, let payload = try? JSONEncoder().encode(OperateRequest(name: "version", options: CLIOptions())),
           let answer = try? channel.send(command: .operate, payload: payload),
           let result = try? JSONDecoder().decode(CLIResult.self, from: answer), result.exitCode == 0,
           let object = try? JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any] {
            app = object["app"] ?? NSNull()
            helper = object["helper"] ?? NSNull()
        }
        return CLIReply.read("version", [
            "cli": ["version": tool.version ?? "unknown", "build": tool.build ?? "unknown"],
            "app": app,
            "helper": helper,
        ])
    }

    /// The JSON patch for `config set <key> <value>`. The value is read as JSON when it parses (true, 60, ["codex"]) and as
    /// text otherwise (timed). Keys outside the settings file are refused, so a typo cannot pass silently.
    static func shorthandPatch(key: String, value: String) -> String? {
        guard CommandCatalog.settingKeys.contains(key) else { return nil }
        let parsed = (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])) ?? value
        guard let data = try? JSONSerialization.data(withJSONObject: [key: parsed], options: [.fragmentsAllowed]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Test seam for real-tempdir coverage: callers inject disk readers/writers
    /// (or in-memory fakes) plus an explicit history choice.
    public static func run(
        argv: [String], channel: (any IPCChannel)?,
        fileReader: (any CLIFileReader)?,
        stdinReader: (any CLIStdinReader)?,
        fileWriter: (any CLIAtomicWriter)?,
        historyStore: (any HistoryStorage)?
    ) -> CLIResult {
        let (name, options) = parse(argv: argv)
        var context = CommandContext(
            channel: channel, fileReader: fileReader, stdinReader: stdinReader,
            fileWriter: fileWriter, historyStore: historyStore)
        return dispatch(name, options: options, context: &context)
    }

    public static func dispatch(_ name: String, options: CLIOptions, context: inout CommandContext) -> CLIResult {
        switch name {
        case "sleep": return sleepCommand(options: options, context: context)
        case "diagnose": return diagnose(options: options, context: context)
        case "watch list", "watch add", "watch remove", "watch enable", "watch disable":
            return watch(name: name, options: options, context: &context)
        case "watch": return fail(2, command: name, reason: "missingSubcommand")
        case "status": return status(context: &context)
        case "agents", "agents list": return agentsList()
        case "config", "config get": return configGet(context: context)
        case "config validate": return configValidate(options: options, context: context)
        case "config set": return configSet(options: options, context: &context)
        case "start": return start(options: options, context: &context)
        case "stop": return stop(context: &context)
        case "logs", "logs export": return logsExport(options: options, context: &context)
        case "recover": return recover(options: options, context: &context)
        case "doctor": return doctor(context: context)
        case "helper install", "helper uninstall", "helper trust", "helper status":
            return helperCommand(name: name, options: options)
        case "helper": return fail(2, command: name, reason: "missingSubcommand")
        case "simulate": return simulate(options: options, context: context)
        case "event", "bridge":
            return fail(3, command: name, reason: "externalObservationOnly")
        case "commands", "help": return CommandCatalog.listing()
        case "version": return versionWithRealIO(channel: context.channel)
        default:
            // A catalogued command that needs the app, reached without one.
            if let spec = CommandCatalog.spec(name), spec.needsApp { return fail(4, command: name, reason: "appUnavailable") }
            return fail(2, command: name.isEmpty ? "none" : name, reason: "unknownCommand")
        }
    }

    private struct WatchConfigSnapshot: Decodable {
        let revision: Int
        let lifetimeRules: [LifetimeRule]?
    }

    private struct WatchRulesPatch: Encodable {
        let lifetimeRules: [LifetimeRule]
    }

    private static func watch(name: String, options: CLIOptions, context: inout CommandContext) -> CLIResult {
        let rules = context.config.lifetimeRules ?? []
        switch name {
        case "watch list":
            guard options.positionals.isEmpty,
                  Set(options.flags.keys).isSubset(of: ["json"]),
                  options.flags.values.allSatisfy({ $0 == "true" }) else {
                return fail(2, command: "watchList", reason: "invalidOptions")
            }
            guard let encoded = try? JSONEncoder().encode(rules),
                  let jsonRules = try? JSONSerialization.jsonObject(with: encoded) else {
                return fail(4, command: "watchList", reason: "invalidConfig")
            }
            return cliJSON(0, ["command": "watchList", "revision": context.revision, "rules": jsonRules])
        case "watch add":
            guard options.positionals.isEmpty,
                  Set(options.flags.keys).isSubset(of: ["executable", "bundle-id", "label"]),
                  (options.flags["executable"] != nil) != (options.flags["bundle-id"] != nil) else {
                return fail(2, command: "watchAdd", reason: "invalidOptions")
            }
            let kind: LifetimeSelectorKind
            let value: String
            if let path = options.flags["executable"] {
                kind = .exactExecutablePath
                value = path
            } else {
                kind = .applicationBundleID
                value = options.flags["bundle-id"] ?? ""
            }
            let label = options.flags["label"] ?? (kind == .exactExecutablePath
                ? URL(fileURLWithPath: value).lastPathComponent
                : value.split(separator: ".").last.map(String.init) ?? value)
            let rule: LifetimeRule
            do { rule = try LifetimeRule(selectorKind: kind, selectorValue: value, label: label) }
            catch { return fail(2, command: "watchAdd", reason: "invalidRule") }
            if kind == .exactExecutablePath {
                guard FileManager.default.isExecutableFile(atPath: value) else {
                    return fail(2, command: "watchAdd", reason: "executableNotFound")
                }
            } else {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value),
                      Bundle(url: appURL)?.bundleIdentifier == value else {
                    return fail(2, command: "watchAdd", reason: "applicationNotInstalled")
                }
            }
            do {
                try LifetimeRule.validateCollection(rules + [rule])
                var patch = ConfigPatch()
                patch.lifetimeRules = rules + [rule]
                context.config = try context.config.applying(patch)
            } catch {
                return fail(2, command: "watchAdd", reason: "invalidRule")
            }
            context.revision += 1
            return cliJSON(0, ["command": "watchAdd", "accepted": true,
                "ruleID": rule.id.uuidString, "revision": context.revision])
        case "watch enable", "watch disable":
            let command = name == "watch enable" ? "watchEnable" : "watchDisable"
            guard options.flags.isEmpty, options.positionals.count == 1,
                  let id = UUID(uuidString: options.positionals[0]) else {
                return fail(2, command: command, reason: "invalidRuleID")
            }
            guard let index = rules.firstIndex(where: { $0.id == id }) else {
                return fail(2, command: command, reason: "ruleNotFound")
            }
            let enabled = name == "watch enable"
            guard rules[index].enabled != enabled else {
                return CLIReply.done(command, changed: false,
                    ["id": id.uuidString, "enabled": enabled, "revision": context.revision])
            }
            var updated = rules
            updated[index].enabled = enabled
            do {
                try LifetimeRule.validateCollection(updated)
                var patch = ConfigPatch()
                patch.lifetimeRules = updated
                context.config = try context.config.applying(patch)
            } catch {
                return fail(2, command: command, reason: "invalidRule")
            }
            return CLIReply.done(command, changed: true, ["id": id.uuidString, "enabled": enabled, "revision": context.revision])
        case "watch remove":
            guard options.flags.isEmpty, options.positionals.count == 1,
                  let id = UUID(uuidString: options.positionals[0]) else {
                return fail(2, command: "watchRemove", reason: "invalidRuleID")
            }
            guard rules.contains(where: { $0.id == id }) else {
                return fail(2, command: "watchRemove", reason: "ruleNotFound")
            }
            let remaining = rules.filter { $0.id != id }
            var patch = ConfigPatch()
            patch.lifetimeRules = remaining
            do { context.config = try context.config.applying(patch) }
            catch { return fail(2, command: "watchRemove", reason: "invalidConfig") }
            context.revision += 1
            return cliJSON(0, ["command": "watchRemove", "accepted": true,
                "ruleID": id.uuidString, "revision": context.revision])
        default:
            return fail(2, command: name, reason: "unknownCommand")
        }
    }

    private static func watchWithRealIO(
        name: String, options: CLIOptions, channel: any IPCChannel
    ) -> CLIResult {
        do {
            let getBytes = try channel.send(command: .configGet, payload: Data())
            let getResult = try JSONDecoder().decode(CLIResult.self, from: getBytes)
            guard getResult.exitCode == 0,
                  let state = try? JSONDecoder().decode(
                    WatchConfigSnapshot.self, from: Data(getResult.json.utf8)),
                  state.revision > 0 else {
                return fail(4, command: name, reason: "invalidAppReply")
            }

            var context = CommandContext()
            context.revision = state.revision
            context.config.lifetimeRules = state.lifetimeRules
            let result = watch(name: name, options: options, context: &context)
            guard result.exitCode == 0, name != "watch list" else { return result }
            // A switch that changes nothing is not written, so the revision does not move.
            if let object = try? JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any],
               object["changed"] as? Bool == false { return result }

            let patch = try JSONEncoder().encode(WatchRulesPatch(lifetimeRules: context.config.lifetimeRules ?? []))
            let request = CLIOptions(flags: [
                "expectedRevision": String(state.revision),
                "patchJSON": String(decoding: patch, as: UTF8.self),
            ])
            let setBytes = try channel.send(command: .configSet, payload: JSONEncoder().encode(request))
            let setResult = try JSONDecoder().decode(CLIResult.self, from: setBytes)
            guard setResult.exitCode == 0 else { return setResult }
            guard let setObject = try? JSONSerialization.jsonObject(
                with: Data(setResult.json.utf8)) as? [String: Any],
                  setObject["accepted"] as? Bool == true,
                  let revision = setObject["revision"] as? Int else {
                return fail(4, command: name, reason: "invalidAppReply")
            }
            guard var output = try? JSONSerialization.jsonObject(
                with: Data(result.json.utf8)) as? [String: Any] else {
                return fail(4, command: name, reason: "invalidAppReply")
            }
            output["revision"] = revision
            output["persisted"] = true
            return cliJSON(0, output)
        } catch let error as IPCError {
            return ipcFail(error, command: name)
        } catch {
            return fail(4, command: name, reason: "invalidAppReply")
        }
    }

    // MARK: - Commands

    static func sleepCommand(options: CLIOptions, context: CommandContext) -> CLIResult {
        guard options.positionals.isEmpty, Set(options.flags.keys).isSubset(of: ["json", "dry-run"]),
              options.flags.values.allSatisfy({ $0 == "true" }) else {
            return fail(2, command: "sleep", reason: "invalidOptions")
        }
        guard let channel = context.channel else { return fail(4, command: "sleep", reason: "appUnavailable") }
        do {
            let payload = try JSONEncoder().encode(options)
            let reply = try channel.send(command: .sleep, payload: payload)
            _ = try BoundedPayload(reply)
            return try JSONDecoder().decode(CLIResult.self, from: reply)
        } catch let error as IPCError { return ipcFail(error, command: "sleep") }
        catch { return fail(4, command: "sleep", reason: "appUnavailable") }
    }
    static func diagnose(options: CLIOptions, context: CommandContext) -> CLIResult {
        guard options.positionals.isEmpty, Set(options.flags.keys).isSubset(of: ["json"]),
              options.flags["json"] == nil || options.flags["json"] == "true" else {
            return fail(2, command: "diagnose", reason: "invalidOptions")
        }
        guard let channel = context.channel else { return fail(4, command: "diagnose", reason: "appUnavailable") }
        do {
            let reply = try channel.send(command: .diagnose, payload: Data())
            _ = try BoundedPayload(reply)
            if let result = try? JSONDecoder().decode(CLIResult.self, from: reply) { return result }
            return fail(4, command: "diagnose", reason: "invalidDiagnosticReply")
        } catch let error as IPCError { return ipcFail(error, command: "diagnose") }
        catch { return fail(4, command: "diagnose", reason: "appUnavailable") }
    }

    static func status(context: inout CommandContext) -> CLIResult {
        guard let channel = context.channel else {
            return cliJSON(4, ["command": "status", "available": false, "reason": "appUnavailable"])
        }
        do {
            let reply = try channel.send(command: .status, payload: Data())
            if let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] {
                var merged = object
                merged["schemaVersion"] = 1
                merged["available"] = true
                return cliJSON(0, merged)
            }
            return cliJSON(0, ["command": "status", "available": true, "detail": String(data: reply, encoding: .utf8) ?? ""])
        } catch let error as IPCError {
            return ipcFail(error, command: "status")
        } catch {
            return fail(4, command: "status", reason: "appUnavailable")
        }
    }

    /// History commands report unavailable until the M4 store lands.
    /// Never synthetic data: empty sessions + available:false, exit 4.
    /// `agents list` needs the app. Without it the reply says so, as every app-backed command does.
    static func agentsList() -> CLIResult {
        CLIReply.refused("agentsList", reason: "appUnavailable")
    }

    static func configGet(context: CommandContext) -> CLIResult {
        var dict = configDict(context.config)
        dict["command"] = "configGet"
        dict["revision"] = context.revision
        return cliJSON(0, dict)
    }

    /// Pure validation, no writes.
    static func configValidate(options: CLIOptions, context: CommandContext) -> CLIResult {
        switch readPatch(command: "configValidate", options: options, context: context) {
        case .failure(let result): return result
        case .success(let patch):
            do {
                _ = try context.config.applying(patch)
                return cliJSON(0, ["command": "configValidate", "valid": true])
            } catch {
                return fail(2, command: "configValidate", reason: "invalidConfig", detail: String(describing: error))
            }
        }
    }

    /// Atomic validated partial patch. `--dry-run` shows the effective diff
    /// without mutating. `--expectedRevision N` conflicts (exit 2, rejected)
    /// when the current revision differs.
    static func configSet(options: CLIOptions, context: inout CommandContext) -> CLIResult {
        let patch: ConfigPatch
        switch readPatch(command: "configSet", options: options, context: context) {
        case .failure(let result): return result
        case .success(let value): patch = value
        }
        if let raw = options.flags["expectedRevision"], Int(raw) == nil || (Int(raw) ?? 0) < 1 {
            return fail(2, command: "configSet", reason: "invalidRevision")
        }
        if let expectedRaw = options.flags["expectedRevision"], let expected = Int(expectedRaw),
           expected != context.revision {
            return cliJSON(2, [
                "command": "configSet", "accepted": false, "reason": "revisionConflict",
                "currentRevision": context.revision, "expectedRevision": expected,
            ])
        }
        let next: Configuration
        do {
            next = try context.config.applying(patch)
        } catch {
            return fail(2, command: "configSet", reason: "invalidConfig", detail: String(describing: error))
        }
        if options.flags["dry-run"] != nil {
            return cliJSON(0, [
                "command": "configSet", "dryRun": true, "valid": true,
                "diff": configDiff(old: context.config, new: next),
            ])
        }
        // A patch that changes nothing is accepted and writes nothing: no new revision, and changed is false.
        guard next != context.config else {
            return CLIReply.done("configSet", changed: false, ["revision": context.revision])
        }
        context.config = next
        context.revision += 1
        return CLIReply.done("configSet", changed: true, [
            "revision": context.revision, "effectiveState": "ready", "reasonCodes": ["configApplied"],
        ])
    }

    /// Explicit session. Duration required for timed (including "infinite"); finite durations are
    /// clamped to the nonresetting cap (reported via capApplied). Safety is
    /// enforced via SafetyPolicy; closed-lid is refused (exit 3) unless the
    /// health snapshot is capability-verified AND the user opted in.
    static func start(options: CLIOptions, context: inout CommandContext) -> CLIResult {
        // The same rules the app applies to a start request (see `StartRequest`), so a refusal here is one there too.
        let request: StartRequest
        switch StartRequest.parse(options) {
        case .refused(let refusal): return refusal
        case .accepted(let value): request = value
        }
        let mode = request.mode
        let modeRaw = mode.rawValue
        let infinite = request.minutes == 0
        let durationSeconds = request.minutes.flatMap { $0 > 0 ? Double($0 * 60) : nil }
        let health: HealthSnapshot = context.health ?? (try! HealthSnapshot())
        let closedLid = request.closedLid
        if closedLid || health.lidState == .closed {
            guard health.capabilityVerified, context.config.closedLidOptIn else {
                return fail(3, command: "start", reason: "closedLidDenied",
                             detail: "closed-lid requires verified capability + opt-in")
            }
        }
        var cpu = CPUObserver()
        let cpuEval = cpu.evaluate(
            cpuPercent: health.cpuPercent, cpuStopEnabled: context.config.cpuStopEnabled,
            now: context.nowMonotonic)
        var safety = SafetyPolicy()
        let signal = safety.evaluate(
            health: health, config: context.config, cpuStop: cpuEval.stop,
            now: context.nowMonotonic)
        guard signal.reasons.isEmpty else {
            return cliJSON(3, [
                "command": "start", "accepted": false, "reason": "safetyDenied",
                "reasonCodes": signal.reasons,
            ])
        }
        if let reason = context.config.batteryEntryRefusal(health: health) {
            return cliJSON(3, ["command": "start", "accepted": false, "reason": "safetyDenied", "reasonCodes": [reason]])
        }
        let batteryBounded = health.powerSource != .ac
        let capSeconds = Double(batteryBounded
            ? min(context.config.runCapMinutes, context.config.batteryCapMinutes) : context.config.runCapMinutes) * 60
        let unlimited = infinite && !batteryBounded
        var requested = durationSeconds ?? capSeconds
        var capApplied = infinite && batteryBounded
        if requested > capSeconds {
            requested = capSeconds
            capApplied = true
        }
        var session = try! ProtectionSession(
            id: "cli-session-\(context.revision)", requestedMode: mode,
            armedClosedLid: closedLid, startedAtMonotonic: context.nowMonotonic,
            capDeadlineMonotonic: unlimited ? nil : context.nowMonotonic + requested)
        let decision = PolicyEngine.evaluate(
            session: session, tasks: [], health: health, config: context.config,
            armed: true, safety: .clear, recoveryConflict: false,
            nowMonotonic: context.nowMonotonic)
        session = decision.session
        context.session = session
        var reasonCodes = decision.reasons
        if capApplied { reasonCodes.append("capClamped") }
        return cliJSON(0, [
            "command": "start", "accepted": true, "mode": modeRaw,
            "effectiveState": decision.state.rawValue, "reasonCodes": reasonCodes,
            "revision": context.revision, "capApplied": capApplied,
            "capDeadline": session.capDeadlineMonotonic.map { $0 as Any } ?? NSNull(),
            "durationUnlimited": unlimited,
        ])
    }

    static func stop(context: inout CommandContext) -> CLIResult {
        guard context.session != nil else {
            return cliJSON(0, [
                "command": "stop", "released": false, "reason": "noActiveSession",
                "cleanupOutcome": "nothingToRelease",
            ])
        }
        context.session = nil
        return cliJSON(0, [
            "command": "stop", "released": true, "reason": "userStop",
            "cleanupOutcome": "enrollmentReleased",
        ])
    }

    /// Bounded redacted export. Refuses to overwrite an existing path unless
    /// `--force`/`--overwrite` is explicit. With no wired history store the
    /// result is honest unavailable (exit 4, never `exported:true`); only a
    /// wired store produces bytes on disk with `exported:true`. Writes are
    /// atomic via the injected writer or the virtual map in tests.
    static func logsExport(options: CLIOptions, context: inout CommandContext) -> CLIResult {
        guard let output = options.flags["output"] else {
            return fail(2, command: "logsExport", reason: "missingOutput")
        }
        let overwrite = options.flags["force"] != nil || options.flags["overwrite"] != nil
        let exists: Bool
        if let writer = context.fileWriter {
            exists = writer.fileExists(atPath: output)
        } else {
            exists = context.files[output] != nil
        }
        if exists, !overwrite {
            return fail(2, command: "logsExport", reason: "overwriteRefused", detail: output)
        }
        guard let storage = context.historyStore else {
            return cliJSON(4, [
                "command": "logsExport", "available": false, "exported": false,
                "reason": "storeUnavailableM4", "output": output,
            ])
        }
        let records = ActivityStore(storage: storage).exportRedacted(salt: UUID().uuidString)
        guard let data = try? JSONEncoder().encode(records) else {
            return fail(2, command: "logsExport", reason: "encodeFailed")
        }
        if let writer = context.fileWriter {
            do {
                try writer.writeAtomically(data, toPath: output, overwrite: overwrite)
            } catch {
                return fail(2, command: "logsExport", reason: "writeFailed", detail: output)
            }
        } else {
            context.files[output] = String(data: data, encoding: .utf8) ?? "{}"
        }
        return cliJSON(0, [
            "command": "logsExport", "exported": true, "output": output,
            "redacted": true, "bounded": true, "eventCount": records.count,
        ])
    }

    /// Dry-run default; owned-only via `RecoveryCommand`. Exit 5 unresolved,
    /// 3 unauthorized/conflict.
    static func recover(options: CLIOptions, context: inout CommandContext) -> CLIResult {
        guard options.flags["owned-only"] != nil || options.flags["ownedOnly"] != nil else {
            return fail(2, command: "recover", reason: "ownedOnlyRequired")
        }
        guard let sessionID = options.flags["session"] ?? context.session?.id else {
            return fail(2, command: "recover", reason: "missingSession")
        }
        let apply = options.flags["apply"] != nil
        var command = RecoveryCommand(
            journal: context.journal, ownerIdentity: context.ownerIdentity,
            channel: context.channel, recoveryService: context.recoveryService)
        let diagnosis = command.run(
            sessionID: sessionID, dryRun: !apply,
            lidState: context.health?.lidState ?? .unknown)
        context.journal = command.journal
        return cliJSON(diagnosis.exitCode, [
            "command": "recover", "outcome": diagnosis.outcome.rawValue,
            "evidence": diagnosis.evidence, "dryRun": !apply,
        ])
    }

    /// Read-only diagnosis. Never mutates config, session, journal, or power.
    static func doctor(context: CommandContext) -> CLIResult {
        var appReachable = false
        if let channel = context.channel {
            appReachable = (try? channel.send(command: .doctor, payload: Data())) != nil
        }
        let configValid = (try? context.config.validate()) != nil
        return cliJSON(0, [
            "command": "doctor", "configValid": configValid,
            "appReachable": appReachable, "journalSessions": context.journal.count,
            "healthIssues": context.health == nil ? ["healthUnknown"] : [String](),
            "revision": context.revision,
        ])
    }

    /// Standard-mode helper lifecycle. Mutating subcommands need administrator rights (`sudo camlid helper ...`);
    /// the installer refuses otherwise. `status` is read-only and works without them.
    static func helperCommand(name: String, options: CLIOptions, installer: HelperInstaller = HelperInstaller()) -> CLIResult {
        let app = options.flags["app"].map { URL(fileURLWithPath: $0) } ?? HelperInstaller.defaultAppBundle
        if name == "helper status" {
            let status = installer.status(appBundle: app)
            let label: String
            switch status {
            case .notInstalled: label = "notInstalled"
            case .installed(let loaded): label = loaded ? "installed" : "installedNotLoaded"
            case .needsReauthorization: label = "needsReauthorization"
            case .needsHelperUpdate: label = "needsHelperUpdate"
            case .helperIdentityMismatch: label = "helperIdentityMismatch"
            case .partial: label = "partial"
            }
            var dict: [String: Any] = ["command": "helperStatus", "status": label, "serviceLoaded": installer.serviceLoaded()]
            if case .partial(let missing) = status { dict["missing"] = missing }
            return cliJSON(0, dict)
        }
        // A QA copy never changes the shared helper, even when `--app` points at one (see `StateLocations`).
        if StateLocations.qaRoot(inAppBundle: app) != nil { return fail(2, command: name, reason: "qaCopy") }
        let result: HelperOperationResult
        switch name {
        case "helper install":
            result = installer.install(appBundle: app, helperSource: options.flags["helper"].map { URL(fileURLWithPath: $0) },
                                       replacePins: options.flags["replace-pins"] != nil)
        case "helper trust": result = installer.trust(appBundle: app)
        default: result = installer.uninstall(force: options.flags["force"] != nil)
        }
        var dict: [String: Any] = ["command": name.replacingOccurrences(of: " ", with: "-"), "accepted": result.accepted, "reason": result.reason]
        if let detail = result.detail { dict["detail"] = detail }
        return cliJSON(result.accepted ? 0 : (result.reason == "administratorRequired" ? 77 : 1), dict)
    }

    /// Isolated simulation. Pure: uses `Simulator` (fake clock/sensors only),
    /// never touches the channel or host power. Output includes
    /// `simulated:true` plus the full transition trace. Reads the scenario or
    /// fixture file from disk (or the injected reader in tests); missing or
    /// invalid input is exit 2. Fixture files report the per-step matrix with
    /// `passed`.
    static func simulate(options: CLIOptions, context: CommandContext) -> CLIResult {
        guard let path = options.flags["scenario"] else {
            return fail(2, command: "simulate", reason: "missingScenario")
        }
        let useCurrent = options.flags["use-current-config"] == "true"
        let data: Data
        do {
            data = try readFileData(atPath: path, context: context)
        } catch {
            return fail(2, command: "simulate", reason: "invalidScenario", detail: path)
        }
        if let fixture = try? JSONDecoder().decode(FixtureFile.self, from: data) {
            // A fixture carries its own configuration, so the saved settings cannot apply to it.
            if useCurrent { return fail(2, command: "simulate", reason: "fixtureHasOwnConfig", detail: path) }
            let result = Simulator(fakeNow: context.nowMonotonic).runFixture(fixture)
            let trace: [[String: Any]] = result.steps.map { step in
                ["at": step.at, "state": step.actual, "reasons": step.actualReasons,
                 "expect": step.expected, "pass": step.passed]
            }
            return cliJSON(0, [
                "command": "simulate", "scenario": result.fixtureName,
                "simulated": true, "passed": result.passed,
                "transitions": trace, "steps": trace,
            ])
        }
        guard let scenario = try? JSONDecoder().decode(
            SimulationScenario.self, from: data) else {
            return fail(2, command: "simulate", reason: "invalidScenario", detail: path)
        }
        var config = context.config
        var source: String?
        if useCurrent {
            guard let saved = savedConfiguration(context: context) else {
                return fail(2, command: "simulate", reason: "invalidSettings", detail: context.settingsURL?.path)
            }
            config = saved.config
            source = saved.source
        }
        let result = Simulator(fakeNow: context.nowMonotonic).run(scenario: scenario, config: config)
        let trace: [[String: Any]] = result.transitions.map { transition in
            ["at": transition.at, "state": transition.state.rawValue, "reasons": transition.reasons]
        }
        var fields: [String: Any] = [
            "command": "simulate", "scenario": result.scenarioName,
            "simulated": true, "transitions": trace,
        ]
        if let source {
            fields["configSource"] = source
            fields["config"] = configDict(config)
        }
        return cliJSON(0, fields)
    }

    /// Saved settings for `simulate --use-current-config`. No saved file means the defaults, as the app uses.
    /// Nil when the file is present but is not a valid saved configuration.
    static func savedConfiguration(context: CommandContext) -> (config: Configuration, source: String)? {
        guard let settingsURL = context.settingsURL else { return nil }
        do {
            let data = try readFileData(atPath: settingsURL.path, context: context)
            guard let saved = PersistedSettings.validated(data) else { return nil }
            return (saved.configuration, "saved")
        } catch CLIFileReadError.notFound(path: _) {
            return (try! Configuration(), "defaults")
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    static func exitFor(_ error: IPCError) -> Int {
        switch error {
        case .unavailable, .busy: return 4
        case .unauthorized: return 3
        case .invalidInput: return 2
        case .policyDenied: return 3
        case .recoveryRequired: return 5
        case .tooLarge: return 2
        }
    }

    static func ipcFail(_ error: IPCError, command: String) -> CLIResult {
        switch error {
        case .unavailable: return fail(4, command: command, reason: "appUnavailable")
        case .busy: return fail(4, command: command, reason: "appBusy")
        case .unauthorized: return fail(3, command: command, reason: "unauthorized")
        case .invalidInput(let detail): return fail(2, command: command, reason: "invalidInput", detail: detail)
        case .policyDenied(let detail): return fail(3, command: command, reason: "policyDenied", detail: detail)
        case .recoveryRequired: return fail(5, command: command, reason: "recoveryRequired")
        case .tooLarge(let size): return fail(2, command: command, reason: "payloadTooLarge", detail: "\(size)")
        }
    }

    /// A refusal with the reason's hint and retry advice (see `CLIReasons`). The caller's exit code wins.
    static func fail(_ code: Int, command: String, reason: String, detail: String? = nil) -> CLIResult {
        CLIReply.refused(command, reason: reason, exit: code, detail: detail)
    }

    static func cliJSON(_ exitCode: Int, _ dict: [String: Any]) -> CLIResult {
        var merged = dict
        merged["schemaVersion"] = 1
        let data = try! JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
        return CLIResult(json: String(data: data, encoding: .utf8) ?? "{\"schemaVersion\":1}", exitCode: exitCode)
    }

    static func configDict(_ config: Configuration) -> [String: Any] {
        let data = try! JSONEncoder().encode(config)
        return (try! JSONSerialization.jsonObject(with: data) as! [String: Any])
    }

    static func configDiff(old: Configuration, new: Configuration) -> [String: Any] {
        let oldDict = configDict(old)
        let newDict = configDict(new)
        var diff: [String: Any] = [:]
        for key in Set(oldDict.keys).union(newDict.keys) {
            let oldValue = oldDict[key].map(canonicalJSON) ?? "missing"
            let newValue = newDict[key].map(canonicalJSON) ?? "missing"
            if oldValue != newValue {
                diff[key] = ["old": oldDict[key] as Any, "new": newDict[key] as Any]
            }
        }
        return diff
    }

    static func canonicalJSON(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    enum PatchRead {
        case success(ConfigPatch)
        case failure(CLIResult)
    }

    static func readPatch(command: String, options: CLIOptions, context: CommandContext) -> PatchRead {
        guard let path = options.flags["file"] else {
            return .failure(fail(2, command: command, reason: "missingFile"))
        }
        let data: Data
        do {
            data = try readFileData(atPath: path, context: context)
        } catch {
            return .failure(fail(2, command: command, reason: "invalidFile", detail: path))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return .failure(fail(2, command: command, reason: "invalidFile", detail: path))
        }
        // F11 CLI half: reject present keys with wrong types or explicit null
        // even before the Core `ConfigPatch` fix lands. Strict decoding throws
        // on String-for-Int etc.; explicit NSNull is rejected outright.
        for key in [
            "mode", "closedLidOptIn", "completionDelayMinutes", "waitRetentionMinutes",
            "batteryFloorPercent", "chargingOnly", "batteryModeAllowed", "batteryEntryPercent", "batteryCapMinutes", "runCapMinutes", "cpuStopEnabled", "allowDisplaySleep",
            "adapterEnrollment", "orcaMetadataConsent", "launchAtLogin", "notificationCategories", "lifetimeRules", "powerMode",
        ] {
            if dict[key] is NSNull {
                return .failure(fail(
                    2, command: command, reason: "invalidConfig",
                    detail: "null value for \(key)"))
            }
        }
        if (try? JSONDecoder().decode(StrictConfigPatchDTO.self, from: data)) == nil {
            // Distinguish malformed JSON (already handled above would be dict
            // failure) from well-formed JSON with wrong value types.
            if (try? JSONSerialization.jsonObject(with: data)) != nil {
                return .failure(fail(
                    2, command: command, reason: "invalidConfig",
                    detail: "wrong type in patch"))
            }
            return .failure(fail(2, command: command, reason: "invalidFile", detail: path))
        }
        do {
            // Wrong-type values also reject in Core (F11 Core half); we consume.
            return .success(try ConfigPatch(jsonDictionary: dict))
        } catch {
            return .failure(fail(2, command: command, reason: "invalidConfig", detail: String(describing: error)))
        }
    }

    /// Reads a file via the injected reader when present, otherwise via the
    /// virtual map (tests). Missing keys and unreadable bytes both surface as
    /// throws so callers emit honest exit-2 reasons.
    static func readFileData(atPath path: String, context: CommandContext) throws -> Data {
        if let reader = context.fileReader {
            return try reader.readFile(atPath: path)
        }
        guard let content = context.files[path] else {
            throw CLIFileReadError.notFound(path: path)
        }
        let data = Data(content.utf8)
        guard data.count <= CLIFileBounds.maxFileBytes else {
            throw CLIFileReadError.tooLarge(path: path, size: data.count)
        }
        return data
    }

}

/// Strict patch shape for F11 wrong-type rejection. Optional fields accept
/// absence, but a present String-for-Int (etc.) throws during decoding.
private struct StrictConfigPatchDTO: Decodable {
    var mode: String?
    var closedLidOptIn: Bool?
    var completionDelayMinutes: Int?
    var waitRetentionMinutes: Int?
    var batteryFloorPercent: Int?
    var chargingOnly: Bool?
    var batteryModeAllowed: Bool?
    var batteryEntryPercent: Int?
    var batteryCapMinutes: Int?
    var runCapMinutes: Int?
    var allowDisplaySleep: Bool?
    var cpuStopEnabled: Bool?
    var adapterEnrollment: [String]?
    var orcaMetadataConsent: Bool?
    var notificationCategories: [NotificationCategory]?
    var lifetimeRules: [LifetimeRule]?
    var launchAtLogin: Bool?
    var powerMode: PowerMode?
}
