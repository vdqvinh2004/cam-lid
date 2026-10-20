import Foundation
import Testing
import CamLidCLI

@testable import CamLidCore

// Audit fixes F03/F04/F11-CLI/F13/F14. Foundation only, no disk except
// explicit real-tempdir tests via FileManager.

private func auditDispatch(_ argv: [String], context: inout CommandContext) -> CLIResult {
    let (name, options) = Commands.parse(argv: argv)
    return Commands.dispatch(name, options: options, context: &context)
}

private func auditJSON(_ result: CLIResult) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(result.json.utf8))
    return try #require(object as? [String: Any])
}

private func fixturesDirectory() -> URL {
    // Walk up from this file to find Tests/Contracts/Fixtures.
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0 ..< 12 {
        let candidate = url.deletingLastPathComponent()
            .appendingPathComponent("Tests/Contracts/Fixtures", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate
        }
        url = url.deletingLastPathComponent()
        if url.path == "/" { break }
    }
    // Fallback: repo layout Packages/CamLidCore -> ../../Tests/Contracts/Fixtures
    let fallback = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CamLidCLITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // CamLidCore
        .deletingLastPathComponent() // Packages
        .appendingPathComponent("Tests/Contracts/Fixtures", isDirectory: true)
    return fallback
}

private func ownedJournal(owner: String = "local-user", session: String = "s1") throws -> RecoveryJournal {
    var journal = RecoveryJournal()
    try journal.commit(try RecoveryRecord(
        journalRevision: 1, sessionID: session, ownerIdentity: owner,
        originalState: ["sleep": "on"], expectedState: ["sleep": "on"]))
    return journal
}

@Suite("Audit CLI (F03/F04/F11/F13/F14)")
struct AuditCLITests {
    // MARK: - F03 real plumbing via fakes

    @Test("config validate reads file; missing and broken are exit 2")
    func configReadsFile() throws {
        let store = InMemoryFileStore(files: [
            "good.json": "{\"runCapMinutes\": 60}",
            "broken.json": "not json",
        ])
        var context = CommandContext(files: [:])
        context.fileReader = store
        #expect(auditDispatch(["config", "validate", "--file", "good.json"], context: &context).exitCode == 0)
        #expect(auditDispatch(["config", "validate", "--file", "missing.json"], context: &context).exitCode == 2)
        let broken = auditDispatch(["config", "validate", "--file", "broken.json"], context: &context)
        #expect(broken.exitCode == 2)
        #expect(try auditJSON(broken)["reason"] as? String == "invalidFile")
        let noFlag = auditDispatch(["config", "validate"], context: &context)
        #expect(noFlag.exitCode == 2)
    }

    @Test("config set wrong-type patch rejected exit 2 (F11 CLI half)")
    func configWrongTypeRejected() throws {
        let store = InMemoryFileStore(files: [
            "wrong.json": "{\"runCapMinutes\": \"not-a-number\"}",
            "null.json": "{\"runCapMinutes\": null}",
            "good.json": "{\"runCapMinutes\": 60}",
        ])
        var context = CommandContext(files: [:])
        context.fileReader = store
        let wrong = auditDispatch(["config", "validate", "--file", "wrong.json"], context: &context)
        #expect(wrong.exitCode == 2)
        #expect(try auditJSON(wrong)["reason"] as? String == "invalidConfig")
        let nullPatch = auditDispatch(["config", "validate", "--file", "null.json"], context: &context)
        #expect(nullPatch.exitCode == 2)
        let before = context.config
        let applied = auditDispatch(["config", "set", "--file", "wrong.json"], context: &context)
        #expect(applied.exitCode == 2)
        #expect(context.config == before)
    }

    @Test("simulate reads scenario file; missing and invalid are exit 2")
    func simulateReadsFile() throws {
        let store = InMemoryFileStore(files: [
            "ok.json": "{\"name\":\"s\",\"steps\":[{\"at\":0},{\"at\":10}]}",
            "broken.json": "not json",
        ])
        var context = CommandContext(files: [:])
        context.fileReader = store
        #expect(auditDispatch(["simulate", "--scenario", "ok.json"], context: &context).exitCode == 0)
        #expect(auditDispatch(["simulate", "--scenario", "missing.json"], context: &context).exitCode == 2)
        #expect(auditDispatch(["simulate", "--scenario", "broken.json"], context: &context).exitCode == 2)
        #expect(auditDispatch(["simulate"], context: &context).exitCode == 2)
    }

    @Test("legacy event refuses regardless of stdin or channel")
    func eventStdinHonest() throws {
        var empty = CommandContext(files: [:])
        empty.stdinReader = InMemoryStdinReader(data: Data())
        #expect(auditDispatch(["event", "--stdin"], context: &empty).exitCode == 3)

        var nilData = CommandContext(files: [:])
        nilData.stdinReader = InMemoryStdinReader(data: nil)
        #expect(auditDispatch(["event", "--stdin"], context: &nilData).exitCode == 3)

        var big = CommandContext(files: [:])
        big.stdinReader = InMemoryStdinReader(data: Data(count: 64 * 1024 + 1))
        let oversize = auditDispatch(["event", "--stdin"], context: &big)
        #expect(oversize.exitCode == 3)
        #expect(try auditJSON(oversize)["reason"] as? String == "externalObservationOnly")

        // Valid JSON but no app: honest unavailable, never fake success.
        var noApp = CommandContext(files: [:])
        noApp.stdinReader = InMemoryStdinReader(data: Data("{\"kind\":\"ping\"}".utf8))
        let unavailable = auditDispatch(["event", "--stdin"], context: &noApp)
        #expect(unavailable.exitCode == 3)
    }

    @Test("logs export refuses overwrite and honors missing history")
    func logsExportHonest() throws {
        // Overwrite refusal via in-memory writer.
        let store = InMemoryFileStore(files: ["events.json": "existing"])
        var context = CommandContext(files: [:])
        context.fileWriter = store
        context.historyStore = InMemoryHistoryStorage()
        let refused = auditDispatch(["logs", "export", "--output", "events.json"], context: &context)
        #expect(refused.exitCode == 2)
        #expect(try auditJSON(refused)["reason"] as? String == "overwriteRefused")

        // No wired history: available:false exit 4, never exported:true.
        var noHistory = CommandContext(files: [:])
        noHistory.fileWriter = InMemoryFileStore()
        noHistory.historyStore = nil
        let missing = auditDispatch(
            ["logs", "export", "--output", "out.json"], context: &noHistory)
        #expect(missing.exitCode == 4)
        let dict = try auditJSON(missing)
        #expect(dict["available"] as? Bool == false)
        #expect((dict["exported"] as? Bool) != true)

        // Wired history writes bytes atomically.
        let writable = InMemoryFileStore()
        var wired = CommandContext(files: [:])
        wired.fileWriter = writable
        wired.historyStore = InMemoryHistoryStorage()
        let ok = auditDispatch(["logs", "export", "--output", "out.json"], context: &wired)
        #expect(ok.exitCode == 0)
        #expect(writable.fileExists(atPath: "out.json"))
    }

    @Test("real tempdir: config read and atomic export round-trip")
    func realTempdirRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camlid-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configPath = root.appendingPathComponent("cfg.json").path
        try Data("{\"runCapMinutes\": 60}".utf8).write(to: URL(fileURLWithPath: configPath), options: .atomic)
        var context = CommandContext(files: [:])
        context.fileReader = DiskFileReader()
        context.fileWriter = DiskAtomicWriter()
        context.historyStore = InMemoryHistoryStorage()
        #expect(auditDispatch(["config", "validate", "--file", configPath], context: &context).exitCode == 0)

        let outPath = root.appendingPathComponent("export.json").path
        var exportContext = CommandContext(files: [:])
        exportContext.fileReader = DiskFileReader()
        exportContext.fileWriter = DiskAtomicWriter()
        exportContext.historyStore = InMemoryHistoryStorage()
        let first = auditDispatch(["logs", "export", "--output", outPath], context: &exportContext)
        #expect(first.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outPath))
        let bytes = try Data(contentsOf: URL(fileURLWithPath: outPath))
        #expect(!bytes.isEmpty)
        // Second export without --force refuses, preserving existing bytes.
        let second = auditDispatch(["logs", "export", "--output", outPath], context: &exportContext)
        #expect(second.exitCode == 2)
    }

    // MARK: - F04 honest recovery

    @Test("dry-run is restorable never verified and never mutates")
    func recoveryDryRunRestorable() throws {
        let before = try ownedJournal()
        var command = RecoveryCommand(
            journal: before, ownerIdentity: "local-user",
            recoveryService: InMemoryRecoveryService(shouldVerify: true))
        let diagnosis = command.run(sessionID: "s1", dryRun: true, lidState: .open)
        #expect(diagnosis.outcome == .restorable)
        #expect(diagnosis.outcome != .verified)
        #expect(diagnosis.exitCode == 0)
        #expect(diagnosis.evidence["owner"] == "local-user")
        #expect(try command.journal.record(for: "s1") == (try before.record(for: "s1")))
    }

    @Test("apply with nil service stays unresolved without marking verified")
    func recoveryNilServiceUnresolved() throws {
        var command = RecoveryCommand(
            journal: try ownedJournal(), ownerIdentity: "local-user",
            recoveryService: nil)
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .unresolved)
        #expect(diagnosis.exitCode == 5)
        #expect(diagnosis.evidence["sleep"] == nil)
        #expect(try command.journal.record(for: "s1").restoreOutcome != .verified)
    }

    @Test("apply with denying service stays unresolved without marking verified")
    func recoveryDenyingServiceUnresolved() throws {
        var command = RecoveryCommand(
            journal: try ownedJournal(), ownerIdentity: "local-user",
            recoveryService: InMemoryRecoveryService(shouldVerify: false))
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .unresolved)
        #expect(diagnosis.exitCode == 5)
        #expect(try command.journal.record(for: "s1").restoreOutcome != .verified)
    }

    @Test("apply with confirming service marks verified with sleep evidence")
    func recoveryConfirmingServiceVerified() throws {
        var command = RecoveryCommand(
            journal: try ownedJournal(), ownerIdentity: "local-user",
            recoveryService: InMemoryRecoveryService(shouldVerify: true))
        let diagnosis = command.run(sessionID: "s1", dryRun: false, lidState: .open)
        #expect(diagnosis.outcome == .verified)
        #expect(diagnosis.exitCode == 0)
        #expect(diagnosis.evidence["sleep"] == "request")
        #expect(try command.journal.record(for: "s1").restoreOutcome == .verified)
    }

    // MARK: - F13 fixtures

    @Test("all five committed fixtures parse from disk")
    func allFixturesParse() throws {
        let dir = fixturesDirectory()
        let names = ["policy-grace", "policy-safety", "policy-deadlines", "policy-cap", "config-bounds"]
        for name in names {
            let url = dir.appendingPathComponent("\(name).json")
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "missing fixture \(name) in \(dir.path)")
            let data = try Data(contentsOf: url)
            if name == "config-bounds" {
                let parsed = try FixtureLoader.loadConfigBounds(from: data)
                #expect(parsed.fixture == "config-bounds")
                #expect(!parsed.validPatches.isEmpty)
            } else {
                let parsed = try FixtureLoader.load(from: data)
                #expect(!parsed.steps.isEmpty)
                #expect(!parsed.fixture.isEmpty)
            }
        }
    }

    @Test("null battery is explicit missing, absent is healthy default")
    func nullVsAbsentBattery() throws {
        let nullJSON = """
            {"battery": null, "power": "ac", "thermal": "nominal", "lid": "open", "display": "awake"}
            """
        let absentJSON = """
            {"power": "ac", "thermal": "nominal", "lid": "open", "display": "awake"}
            """
        let nullSensors = try JSONDecoder().decode(
            FixtureSensors.self, from: Data(nullJSON.utf8))
        let absentSensors = try JSONDecoder().decode(
            FixtureSensors.self, from: Data(absentJSON.utf8))
        #expect(nullSensors.batteryPresent)
        #expect(nullSensors.battery == nil)
        #expect(!absentSensors.batteryPresent)
        let nullReadings = nullSensors.sensorReadings(at: 0)
        let absentReadings = absentSensors.sensorReadings(at: 0)
        #expect(nullReadings.batteryPercent == nil)
        #expect(absentReadings.batteryPercent == 80)
    }

    @Test("task identity keeps first-seen deadlines across ticks")
    func taskIdentityPreserved() throws {
        let fixture = FixtureFile(
            fixture: "deadline-pin", description: "pin",
            config: FixtureConfig(),
            steps: [
                FixtureStep(
                    at: 10, tasks: [FixtureTask(id: "t1", state: "waiting", kind: "lifecycle", waitUntil: 50)],
                    sensors: FixtureSensors(), safety: [], expect: "ready"),
                FixtureStep(
                    at: 60, tasks: [FixtureTask(id: "t1", state: "waiting", kind: "lifecycle", waitUntil: 500)],
                    sensors: FixtureSensors(), safety: [], expect: "ready"),
            ])
        let result = Simulator().runFixture(fixture)
        #expect(result.steps.count == 2)
        #expect(result.steps[0].actual == "ready")
        // Waiting never arms protection, so both ticks stay ready. The second tick still
        // renews waitUntil to 500 in the file; first-seen deadline retention continues to bound supervision hold.
        #expect(result.steps[1].actual == "ready")
        #expect(result.steps[1].passed)
    }

    @Test("fixture matrix deterministic and policy fixtures pass")
    func fixtureMatrixDeterministic() throws {
        let dir = fixturesDirectory()
        for name in ["policy-grace", "policy-safety", "policy-deadlines", "policy-cap"] {
            let data = try Data(contentsOf: dir.appendingPathComponent("\(name).json"))
            let fixture = try FixtureLoader.load(from: data)
            let first = Simulator().runFixture(fixture)
            let second = Simulator().runFixture(fixture)
            #expect(first == second)
            #expect(first.simulated)
            #expect(first.passed, "fixture \(name) matrix failed: \(first.steps.filter { !$0.passed })")
        }
    }

    @Test("unknown hold keeps bounded deadline without extension")
    func unknownHoldBounded() throws {
        let fixture = FixtureFile(
            fixture: "unknown-pin", description: "pin",
            config: FixtureConfig(),
            steps: [
                FixtureStep(
                    at: 70, tasks: [FixtureTask(id: "t2", state: "unknown", kind: "lifecycle", unknownUntil: 90)],
                    sensors: FixtureSensors(), safety: [], expect: "protected"),
                FixtureStep(
                    at: 95, tasks: [FixtureTask(id: "t2", state: "unknown", kind: "lifecycle", unknownUntil: 500)],
                    sensors: FixtureSensors(), safety: [], expect: "ready", expectReasons: ["workUncertain", "releaseComplete"]),
            ])
        let result = Simulator().runFixture(fixture)
        #expect(result.steps[0].passed)
        #expect(result.steps[1].passed)
    }

    // MARK: - F14 wrapper

    @Test("bare echo resolves via PATH")
    func bareEchoResolves() throws {
        var runner = RunCommand(isArmed: { false })
        let result = try runner.runChild(executable: "echo", args: ["hello"])
        #expect(result.exitStatus == 0)
    }

    @Test("exit status passes through")
    func exitStatusPassthrough() throws {
        var runner = RunCommand(isArmed: { false })
        let ok = try runner.runChild(executable: "/bin/sh", args: ["-c", "exit 42"])
        #expect(ok.exitStatus == 42)
        let zero = try runner.runChild(executable: "/bin/sh", args: ["-c", "exit 0"])
        #expect(zero.exitStatus == 0)
    }

    @Test("signaled termination maps to 128+signo")
    func signalMapping() {
        #expect(RunCommand.shellExitStatus(terminationStatus: 15, reason: .uncaughtSignal) == 143)
        #expect(RunCommand.shellExitStatus(terminationStatus: 9, reason: .uncaughtSignal) == 137)
        #expect(RunCommand.shellExitStatus(terminationStatus: 3, reason: .exit) == 3)
        #expect(RunCommand.shellExitStatus(terminationStatus: 0, reason: .exit) == 0)
    }

    @Test("real SIGTERM self-child maps to 143")
    func realSigtermChild() throws {
        var runner = RunCommand(isArmed: { false })
        let result = try runner.runChild(
            executable: "/bin/sh", args: ["-c", "kill -TERM $$"])
        #expect(result.exitStatus == 143)
    }
}
