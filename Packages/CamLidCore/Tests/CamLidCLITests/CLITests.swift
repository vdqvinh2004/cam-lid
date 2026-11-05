import Foundation
import Testing
import CamLidCLI

@testable import CamLidCore

// Library-level contract checks for specs/007-ai-quality-gate T001:
// schemaVersion, exit-code mapping, bounds, and never-synthetic states.

struct StubChannel: IPCChannel, Sendable {
    var handler: @Sendable (AllowlistedCommand, Data) throws -> Data
    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        try handler(command, payload)
    }
}

func okChannel(_ json: String = "{\"mode\":\"auto\"}") -> StubChannel {
    StubChannel(handler: { _, _ in Data(json.utf8) })
}

func healthySnapshot(closedLid: Bool = false, capability: Bool = true) throws -> HealthSnapshot {
    try HealthSnapshot(
        batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
        cpuPercent: 10, lidState: closedLid ? .closed : .open,
        internalDisplayState: .awake, capabilityVerified: capability)
}

func jsonDict(_ result: CLIResult) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(result.json.utf8))
    return try #require(object as? [String: Any])
}

func schema(_ result: CLIResult) throws -> Int {
    let dict = try jsonDict(result)
    return try #require(dict["schemaVersion"] as? Int)
}

func dispatch(_ argv: [String], context: inout CommandContext) -> CLIResult {
    let (name, options) = Commands.parse(argv: argv)
    return Commands.dispatch(name, options: options, context: &context)
}

func ownedContext() throws -> CommandContext {
    var context = CommandContext(files: [
        "valid.json": "{\"runCapMinutes\": 60}",
        "bad-range.json": "{\"runCapMinutes\": 999}",
        "bad-key.json": "{\"nope\": 1}",
        "scenario.json": "{\"name\":\"s\",\"steps\":[{\"at\":0},{\"at\":10}]}",
        "broken.json": "not json",
    ])
    var journal = RecoveryJournal()
    try journal.commit(try RecoveryRecord(
        journalRevision: 1, sessionID: "s1", ownerIdentity: "local-user",
        originalState: ["sleep": "on"], expectedState: ["sleep": "on"]))
    try journal.commit(try RecoveryRecord(
        journalRevision: 1, sessionID: "foreign", ownerIdentity: "other-user",
        originalState: ["sleep": "on"], expectedState: ["sleep": "on"]))
    context.journal = journal
    return context
}

@Suite("CLI contract checks (007-T001)")
struct CLITests {
    @Test func explicitInfiniteTimerHasNullDeadlineAndStillRejectsUnsafeStart() throws {
        var context = CommandContext(); context.health = try healthySnapshot()
        let started = dispatch(["start", "--mode", "timed", "--duration", "infinite"], context: &context)
        let json = try jsonDict(started)
        #expect(started.exitCode == 0 && json["capDeadline"] is NSNull)
        #expect(context.session?.capDeadlineMonotonic == nil)
        context.health = try HealthSnapshot(batteryPercent: 10, powerSource: .ac, thermalPressure: .critical, lidState: .open)
        #expect(dispatch(["start", "--mode", "timed", "--duration", "infinite"], context: &context).exitCode == 3)
    }
    @Test("every command emits schemaVersion 1")
    func everyCommandHasSchemaVersion() throws {
        var context = try ownedContext()
        context.health = try healthySnapshot()
        context.channel = okChannel()
        context.stdinData = Data("{\"kind\":\"ping\"}".utf8)
        var results: [CLIResult] = []
        results.append(dispatch(["status", "--json"], context: &context))
        results.append(dispatch(["agents", "list", "--json"], context: &context))
        results.append(dispatch(["config", "get", "--json"], context: &context))
        results.append(dispatch(["config", "validate", "--file", "valid.json"], context: &context))
        results.append(dispatch(["config", "validate", "--file", "bad-range.json"], context: &context))
        results.append(dispatch(["config", "set", "--file", "valid.json", "--dry-run"], context: &context))
        results.append(dispatch(["config", "set", "--file", "valid.json"], context: &context))
        results.append(dispatch(["start", "--mode", "auto"], context: &context))
        results.append(dispatch(["start", "--mode", "timed"], context: &context))
        results.append(dispatch(["stop"], context: &context))
        results.append(dispatch(["logs", "export", "--output", "events.json", "--redacted"], context: &context))
        results.append(dispatch(["recover", "--owned-only", "--dry-run", "--session", "nope"], context: &context))
        results.append(dispatch(["doctor", "--json"], context: &context))
        results.append(dispatch(["simulate", "--scenario", "scenario.json"], context: &context))
        results.append(dispatch(["simulate", "--scenario", "broken.json"], context: &context))
        results.append(dispatch(["event", "--stdin"], context: &context))
        results.append(dispatch(["run"], context: &context))
        results.append(dispatch(["bogus"], context: &context))
        results.append(dispatch([], context: &context))
        #expect(!results.isEmpty)
        for result in results {
            #expect(try schema(result) == 1)
        }
    }

    @Test("exit-code mapping table")
    func exitCodeMapping() throws {
        var cases: [(argv: [String], code: Int)] = []
        cases.append((["bogus"], 2))
        cases.append((["config", "validate", "--file", "bad-range.json"], 2))
        cases.append((["config", "validate", "--file", "bad-key.json"], 2))
        cases.append((["config", "validate"], 2))
        cases.append((["start", "--mode", "timed"], 2))
        cases.append((["start", "--mode", "bogus"], 2))
        cases.append((["agents", "list"], 4))
        cases.append((["status"], 4)) // nil channel: app unavailable
        cases.append((["recover", "--owned-only", "--dry-run", "--session", "nope"], 5))
        for (argv, code) in cases {
            var context = try ownedContext()
            let result = dispatch(argv, context: &context)
            #expect(result.exitCode == code, "argv \(argv) exited \(result.exitCode), want \(code)")
        }
        // Closed-lid denied without capability.
        var closed = try ownedContext()
        closed.health = try healthySnapshot(closedLid: true, capability: false)
        #expect(dispatch(["start", "--mode", "auto", "--closed-lid"], context: &closed).exitCode == 3)
        // Conflict maps to 3.
        var conflict = try ownedContext()
        let conflicted = dispatch(
            ["recover", "--owned-only", "--dry-run", "--session", "foreign"], context: &conflict)
        #expect(conflicted.exitCode == 3)
        // Success paths exit 0.
        var ok = try ownedContext()
        ok.health = try healthySnapshot()
        #expect(dispatch(["start", "--mode", "auto"], context: &ok).exitCode == 0)
        #expect(dispatch(["doctor"], context: &ok).exitCode == 0)
        #expect(dispatch(["stop"], context: &ok).exitCode == 0)
    }

    @Test("invalid config rejected with exit 2")
    func invalidConfigRejected() throws {
        var context = try ownedContext()
        for file in ["bad-range.json", "bad-key.json", "broken.json"] {
            let result = dispatch(["config", "validate", "--file", file], context: &context)
            #expect(result.exitCode == 2)
            #expect(try schema(result) == 1)
        }
        let before = context.config
        let applied = dispatch(["config", "set", "--file", "bad-range.json"], context: &context)
        #expect(applied.exitCode == 2)
        #expect(context.config == before) // atomic: no half-apply
    }

    @Test("expectedRevision conflict rejected")
    func revisionConflict() throws {
        var context = try ownedContext()
        let result = dispatch(
            ["config", "set", "--file", "valid.json", "--expectedRevision", "99"], context: &context)
        #expect(result.exitCode == 2)
        let dict = try jsonDict(result)
        #expect(dict["reason"] as? String == "revisionConflict")
        #expect(dict["currentRevision"] as? Int == 1)
        #expect(context.revision == 1)
    }

    @Test("legacy event is denied before reading oversized data")
    func oversizeEvent() throws {
        var context = try ownedContext()
        context.channel = okChannel()
        context.stdinData = Data(count: 64 * 1024 + 1)
        let result = dispatch(["event", "--stdin"], context: &context)
        #expect(result.exitCode == 3)
        let dict = try jsonDict(result)
        #expect(dict["reason"] as? String == "externalObservationOnly")
    }

    @Test("agents list unavailable, never synthetic")
    func agentsNeverSynthetic() throws {
        var context = try ownedContext()
        context.channel = okChannel()
        let result = dispatch(["agents", "list"], context: &context)
        #expect(result.exitCode == 4)
        let dict = try jsonDict(result)
        #expect(dict["available"] as? Bool == false)
        #expect((dict["sessions"] as? [Any])?.isEmpty == true)
    }

    @Test("closed-lid start refused without capability, allowed with it")
    func closedLidGate() throws {
        var denied = try ownedContext()
        denied.health = try healthySnapshot(closedLid: true, capability: false)
        let refused = dispatch(["start", "--mode", "auto", "--closed-lid"], context: &denied)
        #expect(refused.exitCode == 3)
        #expect(try jsonDict(refused)["reason"] as? String == "closedLidDenied")
        #expect(denied.session == nil)

        var allowed = try ownedContext()
        allowed.health = try healthySnapshot(closedLid: true, capability: true)
        allowed.config = try allowed.config.applying(
            try ConfigPatch(jsonDictionary: ["closedLidOptIn": true]))
        let started = dispatch(["start", "--mode", "auto", "--closed-lid"], context: &allowed)
        #expect(started.exitCode == 0)
        #expect(allowed.session != nil)
    }

    @Test("logs export refuses overwrite")
    func logsRefuseOverwrite() throws {
        var context = try ownedContext()
        context.files["events.json"] = "existing"
        let refused = dispatch(["logs", "export", "--output", "events.json"], context: &context)
        #expect(refused.exitCode == 2)
        #expect(try jsonDict(refused)["reason"] as? String == "overwriteRefused")
        #expect(context.files["events.json"] == "existing")
        let forced = dispatch(
            ["logs", "export", "--output", "events.json", "--force"], context: &context)
        #expect(forced.exitCode == 0)
    }

    @Test("simulate output marks simulated with trace")
    func simulateMarksSimulated() throws {
        var context = try ownedContext()
        let result = dispatch(["simulate", "--scenario", "scenario.json"], context: &context)
        #expect(result.exitCode == 0)
        let dict = try jsonDict(result)
        #expect(dict["simulated"] as? Bool == true)
        #expect((dict["transitions"] as? [Any])?.count == 2)
        #expect(dict["configSource"] == nil)
    }

    @Test("simulate --use-current-config uses the saved settings and names them")
    func simulateUsesSavedSettings() throws {
        var context = try ownedContext()
        var saved = try Configuration()
        saved.mode = .timed
        let file = PersistedSettings(schemaVersion: 1, revision: 2, configuration: saved)
        context.files[PersistedSettings.defaultURL.path] = String(decoding: try JSONEncoder().encode(file), as: UTF8.self)
        let result = dispatch(["simulate", "--scenario", "scenario.json", "--use-current-config"], context: &context)
        #expect(result.exitCode == 0)
        let dict = try jsonDict(result)
        #expect(dict["configSource"] as? String == "saved")
        #expect((dict["config"] as? [String: Any])?["mode"] as? String == "timed")
    }

    @Test("simulate --use-current-config uses the defaults when nothing is saved and refuses a broken file")
    func simulateUseCurrentConfigFallbacks() throws {
        var context = try ownedContext()
        let missing = dispatch(["simulate", "--scenario", "scenario.json", "--use-current-config"], context: &context)
        #expect(missing.exitCode == 0)
        #expect(try jsonDict(missing)["configSource"] as? String == "defaults")
        context.files[PersistedSettings.defaultURL.path] = "not json"
        let broken = dispatch(["simulate", "--scenario", "scenario.json", "--use-current-config"], context: &context)
        #expect(broken.exitCode == 2)
        #expect(try jsonDict(broken)["reason"] as? String == "invalidSettings")
    }

    @Test("run without the app is refused before attempting a missing command")
    func runLaunchFailure() throws {
        let result = Commands.runWithRealIO(argv: ["run", "--", "/nonexistent-camlid-probe"], channel: nil)
        #expect(result.exitCode == 4)
        #expect(try jsonDict(result)["reason"] as? String == "appUnavailable")
    }

    @Test("parse router handles flags, equals, and double-dash")
    func parseRouter() {
        let (name, options) = Commands.parse(argv: ["config", "set", "--file", "a.json", "--dry-run"])
        #expect(name == "config set")
        #expect(options.flags["file"] == "a.json")
        #expect(options.flags["dry-run"] == "true")
        let (run, runOptions) = Commands.parse(argv: ["run", "--", "/bin/echo", "hi"])
        #expect(run == "run")
        #expect(runOptions.positionals == ["/bin/echo", "hi"])
        let (eq, eqOptions) = Commands.parse(argv: ["start", "--mode=timed", "--duration=30m"])
        #expect(eq == "start")
        #expect(eqOptions.flags["mode"] == "timed")
        #expect(eqOptions.flags["duration"] == "30m")
    }
}
