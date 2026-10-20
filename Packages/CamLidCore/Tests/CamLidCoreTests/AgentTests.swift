/// Agent integration tests (M3 T008, test half only).
///
/// Unit-level lifecycle/edge cases using inline JSON plus the evidence
/// normalizer, asserting states via normalizer outcomes and
/// `PolicyEngine.holdsSession`. No 20-run provider evidence is recorded here
/// and nothing is written to docs/qa: installed-version runs belong to a
/// separate validation pass.
import Foundation
import Testing

@testable import CamLidCore

private func jsonData(_ text: String) -> Data { Data(text.utf8) }

private func appliedTask(_ outcome: NormalizeOutcome) throws -> AgentTask {
    guard case let .applied(task) = outcome else {
        Issue.record("expected applied, got \(outcome)")
        return try AgentTask(
            id: "fallback", sessionID: "s", runID: "r", state: .unknown,
            evidenceKind: .process, confidence: .unknown)
    }
    return task
}

private func manualEvent(
    provider: String = "claude", session: String = "s1", run: String = "r1",
    state: TaskState, sequence: Int, epoch: Int = 0, received: Double = 1000,
    parent: String? = nil
) throws -> NormalizedEvent {
    try NormalizedEvent(
        provider: provider, sessionID: session, runID: run, parentRunID: parent,
        state: state, evidenceKind: .lifecycle, confidence: .exact,
        sequence: sequence, epoch: epoch, receivedMonotonic: received)
}

@Suite("Agent integration (T008 unit half)")
struct AgentTests {
    // MARK: - Lifecycle races (reordered events)

    @Test("reordered delivery applies in sequence order via buffer")
    func reorderedRace() throws {
        var normalizer = EvidenceNormalizer()
        let late = try manualEvent(state: .completed, sequence: 1, received: 1001)
        let early = try manualEvent(state: .working, sequence: 0, received: 1000)
        #expect(normalizer.normalize(late) == .buffered)
        let outcome = normalizer.normalize(early)
        let task = try appliedTask(outcome)
        #expect(task.state == .completed)
        #expect(PolicyEngine.holdsSession(task, now: 1002) == false)
        // Replay of the terminal sequence hits the tombstone: rejected as
        // closed-run, not a reopen and never a resurrection.
        #expect(normalizer.normalize(late) == .lateRejected(reason: "closedRun"))
        #expect(normalizer.task(provider: "claude", sessionID: "s1", runID: "r1")?.state == .completed)
    }

    @Test("batch entry sorts reordered events before applying")
    func batchSortsReordered() throws {
        var normalizer = EvidenceNormalizer()
        let events = try [
            manualEvent(state: .completed, sequence: 2, received: 1002),
            manualEvent(state: .working, sequence: 0, received: 1000),
            manualEvent(state: .working, sequence: 1, received: 1001),
        ]
        let outcomes = normalizer.normalizeBatch(events)
        #expect(outcomes.count == 3)
        #expect(outcomes.allSatisfy {
            if case .applied = $0 { return true } else { return false }
        })
        #expect(normalizer.task(provider: "claude", sessionID: "s1", runID: "r1")?.state == .completed)
    }

    // MARK: - Reconnect (epoch reset)

    @Test("reconnect epoch reports reset and requires fresh numbering")
    func reconnectEpochReset() throws {
        var claude = ClaudeAdapter(optIn: true)
        var normalizer = EvidenceNormalizer()
        let first = claude.parse(json:
            jsonData(#"{"hook":"UserPromptSubmit","session_id":"s-re"}"#), receivedMonotonic: 1000)
        guard case let .event(event0) = first else {
            Issue.record("expected event, got \(first)")
            return
        }
        _ = normalizer.normalize(event0)
        claude.noteReconnect(sessionID: "s-re")
        let second = claude.parse(json:
            jsonData(#"{"hook":"UserPromptSubmit","session_id":"s-re"}"#), receivedMonotonic: 1100)
        guard case let .event(event1) = second else {
            Issue.record("expected event, got \(second)")
            return
        }
        #expect(event1.epoch == 1)
        #expect(event1.sequence == 0)
        guard case let .epochReset(generation) = normalizer.normalize(event1) else {
            Issue.record("expected epochReset")
            return
        }
        #expect(generation == 1)
        // After reconcile, the fresh generation applies normally.
        let task = try appliedTask(normalizer.normalize(event1))
        #expect(task.state == .working)
        #expect(PolicyEngine.holdsSession(task, now: 1101))
    }

    // MARK: - Approval wait (waiting inside deadline)

    @Test("permission wait holds inside the wait deadline only")
    func approvalWait() throws {
        var opencode = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        var normalizer = EvidenceNormalizer() // 300s wait default
        let parsed = opencode.parse(json:
            jsonData(#"{"type":"permission.request","session_id":"s-approval"}"#),
            receivedMonotonic: 2000)
        guard case let .event(event) = parsed else {
            Issue.record("expected event, got \(parsed)")
            return
        }
        let task = try appliedTask(normalizer.normalize(event))
        #expect(task.state == .waiting)
        #expect(task.waitUntilMonotonic == 2300)
        #expect(PolicyEngine.holdsSession(task, now: 2299))
        #expect(!PolicyEngine.holdsSession(task, now: 2300))
    }

    // MARK: - Network gap (unknown bounded)

    @Test("lost evidence degrades to bounded unknown")
    func networkGapUnknownBounded() throws {
        var normalizer = EvidenceNormalizer() // 120s unknown default
        let working = try manualEvent(
            session: "s-gap", run: "r-gap", state: .working, sequence: 0, received: 3000)
        let held = try appliedTask(normalizer.normalize(working))
        #expect(PolicyEngine.holdsSession(held, now: 3001))
        let unknown = try manualEvent(
            session: "s-gap", run: "r-gap", state: .unknown, sequence: 1, received: 3100)
        let degraded = try appliedTask(normalizer.normalize(unknown))
        #expect(degraded.state == .unknown)
        #expect(degraded.unknownUntilMonotonic == 3220)
        #expect(PolicyEngine.holdsSession(degraded, now: 3219))
        #expect(!PolicyEngine.holdsSession(degraded, now: 3220))
    }

    // MARK: - Crash (failed) plus tombstones

    @Test("turn failure tombstones the run until the session ends")
    func crashTombstone() throws {
        var codex = CodexAdapter(optIn: true)
        var normalizer = EvidenceNormalizer()
        let started = codex.parseJSONLine(
            #"{"type":"turn.started","session_id":"s-crash","turn_id":"t1"}"#, receivedMonotonic: 4000)
        guard case let .event(begin) = started else {
            Issue.record("expected event, got \(started)")
            return
        }
        _ = normalizer.normalize(begin)
        let failedLine = codex.parseJSONLine(
            #"{"type":"turn.failed","session_id":"s-crash","turn_id":"t1"}"#, receivedMonotonic: 4010)
        guard case let .event(failed) = failedLine else {
            Issue.record("expected event, got \(failedLine)")
            return
        }
        let crashed = try appliedTask(normalizer.normalize(failed))
        #expect(crashed.state == .failed)
        #expect(!PolicyEngine.holdsSession(crashed, now: 4011))
        // Same run ID reused for fresh work is rejected: mint a new run.
        let stale = try manualEvent(
            provider: "codex", session: "s-crash", run: "t1",
            state: .working, sequence: 2, received: 4020)
        guard case let .reusedRunRejected(reason) = normalizer.normalize(stale) else {
            Issue.record("expected reusedRunRejected")
            return
        }
        #expect(!reason.isEmpty)
        // Tombstones clear when the session ends: IDs become reusable.
        normalizer.endSession(provider: "codex", sessionID: "s-crash")
        let fresh = try manualEvent(
            provider: "codex", session: "s-crash", run: "t1",
            state: .working, sequence: 0, received: 4100)
        let revived = try appliedTask(normalizer.normalize(fresh))
        #expect(revived.state == .working)
    }

    @Test("normalizer rejects invalid, stale, and overflowing input")
    func rejectionPaths() throws {
        var normalizer = EvidenceNormalizer(maxReorderWindow: 1)
        // Self-parented events are invalid.
        let selfParent = try manualEvent(state: .working, sequence: 0, parent: "r1")
        #expect(normalizer.normalize(selfParent) == .lateRejected(reason: "selfParent"))
        // Ahead-of-gap buffering is bounded.
        let events = try [
            manualEvent(session: "s-buf", run: "r-buf", state: .working, sequence: 0),
            manualEvent(session: "s-buf", run: "r-buf", state: .working, sequence: 2),
            manualEvent(session: "s-buf", run: "r-buf", state: .working, sequence: 3),
        ]
        #expect(normalizer.normalize(events[0]) == .applied(task: normalizer.task(
            provider: "claude", sessionID: "s-buf", runID: "r-buf")!))
        #expect(normalizer.normalize(events[1]) == .buffered)
        #expect(normalizer.normalize(events[2]) == .lateRejected(reason: "reorderBufferFull"))
        // Stale generations are rejected.
        var epochProbe = EvidenceNormalizer()
        let old = try manualEvent(
            session: "s-ep", run: "r-ep", state: .working, sequence: 0, epoch: 2)
        _ = epochProbe.normalize(old)
        let older = try manualEvent(
            session: "s-ep", run: "r-ep", state: .working, sequence: 5, epoch: 1)
        #expect(epochProbe.normalize(older) == .lateRejected(reason: "staleEpoch"))
    }

    // MARK: - Child tasks

    @Test("parent stop does not clear a tracked working child")
    func childTasks() throws {
        var claude = ClaudeAdapter(optIn: true)
        var normalizer = EvidenceNormalizer()
        let prompt = claude.parse(json:
            jsonData(#"{"hook":"UserPromptSubmit","session_id":"s-child"}"#),
            receivedMonotonic: 5000)
        guard case let .event(parentBegin) = prompt else {
            Issue.record("expected event, got \(prompt)")
            return
        }
        _ = normalizer.normalize(parentBegin)
        let spawn = claude.parse(json:
            jsonData(#"{"hook":"SubagentStart","session_id":"s-child","subagent_id":"kid-1"}"#),
            receivedMonotonic: 5001)
        guard case let .event(childBegin) = spawn else {
            Issue.record("expected event, got \(spawn)")
            return
        }
        #expect(childBegin.parentRunID == "main")
        let childTask = try appliedTask(normalizer.normalize(childBegin))
        #expect(childTask.state == .working)
        #expect(normalizer.childRunIDs(
            provider: "claude", sessionID: "s-child", parentRunID: "main") == ["kid-1"])
        // Root Stop ends the parent turn while the child still works.
        let stop = claude.parse(json:
            jsonData(#"{"hook":"Stop","session_id":"s-child"}"#), receivedMonotonic: 5002)
        guard case let .event(parentEnd) = stop else {
            Issue.record("expected event, got \(stop)")
            return
        }
        let parentTask = try appliedTask(normalizer.normalize(parentEnd))
        #expect(parentTask.state == .idle)
        #expect(!PolicyEngine.holdsSession(parentTask, now: 5003))
        #expect(PolicyEngine.holdsSession(childTask, now: 5003))
        // Child completion is tracked by its own explicit run ID.
        let childStop = claude.parse(json:
            jsonData(
                #"{"hook":"SubagentStop","session_id":"s-child","subagent_id":"kid-1"}"#),
            receivedMonotonic: 5004)
        guard case let .event(childEnd) = childStop else {
            Issue.record("expected event, got \(childStop)")
            return
        }
        let finished = try appliedTask(normalizer.normalize(childEnd))
        #expect(finished.state == .completed)
        #expect(!PolicyEngine.holdsSession(finished, now: 5005))
    }

    // MARK: - Parallel sessions

    @Test("parallel sessions track independently")
    func parallelSessions() throws {
        var normalizer = EvidenceNormalizer()
        let first = try manualEvent(session: "s-a", run: "main", state: .working, sequence: 0)
        let second = try manualEvent(session: "s-b", run: "main", state: .working, sequence: 0)
        let taskA = try appliedTask(normalizer.normalize(first))
        let taskB = try appliedTask(normalizer.normalize(second))
        #expect(PolicyEngine.holdsSession(taskA, now: 1001))
        #expect(PolicyEngine.holdsSession(taskB, now: 1001))
        let doneA = try manualEvent(session: "s-a", run: "main", state: .completed, sequence: 1)
        let finishedA = try appliedTask(normalizer.normalize(doneA))
        #expect(!PolicyEngine.holdsSession(finishedA, now: 1002))
        #expect(PolicyEngine.holdsSession(taskB, now: 1002))
        #expect(normalizer.tasksInSession(provider: "claude", sessionID: "s-b").count == 1)
    }

    // MARK: - Version mismatch

    @Test("orca version mismatch never reports exact")
    func versionMismatch() throws {
        let resolver = OrcaHostResolver()
        let status = try JSONDecoder().decode(
            OrcaStatusPayload.self,
            from: jsonData(
                #"{"version":"1.3.9","app_running":true,"runtime_state":"ready"}"#))
        let rows = try JSONDecoder().decode(
            [OrcaWorktreeRow].self,
            from: jsonData(
                #"[{"session_id":"s-old","host":"local","state":"working"}]"#))
        let resolution = resolver.resolve(
            status: status, rows: rows, snapshotMonotonic: 6000,
            receivedMonotonic: 6000, nowMonotonic: 6001)
        #expect(resolution.versionMismatch)
        #expect(resolution.events.count == 1)
        #expect(resolution.events[0].confidence == .inferred)
        #expect(resolution.events[0].confidence != .exact)
        #expect(resolution.claimedSessionIDs == ["s-old"])
    }

    @Test("orca rejects restored-unconfirmed working and non-local scope")
    func orcaScopeGates() throws {
        let resolver = OrcaHostResolver()
        let status = OrcaStatusPayload(version: "1.4.219")
        let rows = [
            OrcaWorktreeRow(
                sessionID: "s-restored", host: "local",
                restoredUnconfirmed: true, agentState: "working"),
            OrcaWorktreeRow(sessionID: "s-remote", host: "remote", agentState: "working"),
            OrcaWorktreeRow(sessionID: "s-noscope", agentState: "working"),
            OrcaWorktreeRow(sessionID: "s-dup", host: "local", agentState: "working"),
        ]
        let resolution = resolver.resolve(
            status: status, rows: rows, snapshotMonotonic: 7000,
            receivedMonotonic: 7000, nowMonotonic: 7001,
            claimedByOtherProviders: ["s-dup"])
        // Restored-but-unconfirmed degrades to unknown, never working.
        let restored = resolution.events.first { $0.sessionID == "s-restored" }
        #expect(restored?.state == .unknown)
        #expect(restored?.confidence == .unknown)
        let reasons = Dictionary(
            uniqueKeysWithValues: resolution.rejections.map { ($0.sessionID, $0.reason) })
        #expect(reasons["s-remote"] == "remoteScope")
        #expect(reasons["s-noscope"] == "unknownScope")
        #expect(reasons["s-dup"] == "duplicateSession")
        #expect(!resolution.versionMismatch)
    }

    @Test("stale orca snapshot degrades known runs to unknown")
    func orcaStaleSnapshot() throws {
        let resolver = OrcaHostResolver(maxSnapshotAgeSeconds: 15)
        let resolution = resolver.resolve(
            status: OrcaStatusPayload(version: "1.4.219"),
            rows: [OrcaWorktreeRow(sessionID: "s-live", host: "local", agentState: "working")],
            snapshotMonotonic: 8000, receivedMonotonic: 8100, nowMonotonic: 8100,
            previousRuns: [OrcaKnownRun(sessionID: "s-live", runID: "main")])
        #expect(resolution.snapshotStale)
        #expect(resolution.rejections.first?.reason == "staleSnapshot")
        #expect(resolution.events.count == 1)
        #expect(resolution.events[0].state == .unknown)
    }

    // MARK: - Opt-in and scope gates

    @Test("adapters stay disabled without explicit opt-in")
    func optInGating() throws {
        var claude = ClaudeAdapter()
        #expect(claude.parse(json:
            jsonData(#"{"hook":"UserPromptSubmit","session_id":"s"}"#),
            receivedMonotonic: 1) == .ignored(reason: "optInDisabled"))
        var codex = CodexAdapter()
        #expect(codex.parseJSONLine(
            #"{"type":"turn.started","session_id":"s","turn_id":"t"}"#,
            receivedMonotonic: 1) == .ignored(reason: "optInDisabled"))
        var opencode = OpenCodeAdapter(optIn: true)
        #expect(opencode.parse(json:
            jsonData(#"{"type":"status.busy","session_id":"s"}"#),
            receivedMonotonic: 1) == .ignored(reason: "noConfiguredEndpoint"))
        // Idle-prompt notifications are never completion evidence.
        var opted = ClaudeAdapter(optIn: true)
        #expect(opted.parse(json:
            jsonData(
                #"{"hook":"Notification","session_id":"s","notification_type":"idle_prompt"}"#),
            receivedMonotonic: 1) == .ignored(reason: "idlePromptNotCompletion"))
    }

    @Test("codex desktop scope is explicitly unsupported")
    func desktopUnsupported() throws {
        var codex = CodexAdapter(optIn: true)
        #expect(CodexAdapter.unsupportedScopes.contains("desktop"))
        #expect(codex.parse(json:
            jsonData(
                #"{"type":"turn.started","session_id":"s","turn_id":"t","scope":"desktop"}"#),
            receivedMonotonic: 1)
            == .ignored(reason: CodexAdapter.desktopUnsupportedReason))
    }

    // MARK: - OpenCode reconciliation

    @Test("snapshot reconcile merges status and holds parents for children")
    func openCodeReconcile() throws {
        var opencode = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        let snapshot = try JSONDecoder().decode(
            OpenCodeSnapshot.self,
            from: jsonData(
                #"{"sessions":[{"session_id":"p1","status":"idle","child_sessions":["kid-9"]}]}"#))
        // Seed a tracked working child first.
        let childStart = opencode.parse(json:
            jsonData(
                #"{"type":"child.start","session_id":"p1","child_session_id":"kid-9"}"#),
            receivedMonotonic: 9000)
        guard case .event = childStart else {
            Issue.record("expected child event, got \(childStart)")
            return
        }
        let result = opencode.reconcile(
            snapshot: snapshot, takenMonotonic: 9001,
            receivedMonotonic: 9001, nowMonotonic: 9002)
        // Parent idles in the snapshot but a tracked child works: parent held.
        let parent = result.events.first { $0.sessionID == "p1" }
        #expect(parent?.state == .working)
        #expect(result.notes.contains("parentHeldForChildren:p1"))
        #expect(opencode.reconcileAttempts == 0)
    }

    @Test("snapshot retry is bounded")
    func openCodeRetryBounded() throws {
        var opencode = OpenCodeAdapter(optIn: true, endpoint: "127.0.0.1:4096")
        let snapshot = OpenCodeSnapshot(sessions: [])
        for _ in 0..<OpenCodeAdapter.maxReconcileAttempts {
            _ = opencode.reconcile(
                snapshot: snapshot, takenMonotonic: 0,
                receivedMonotonic: 9500, nowMonotonic: 9500)
        }
        #expect(opencode.reconcileAttempts == OpenCodeAdapter.maxReconcileAttempts)
        #expect(!opencode.shouldRetrySnapshot)
        let final = opencode.reconcile(
            snapshot: snapshot, takenMonotonic: 0,
            receivedMonotonic: 9600, nowMonotonic: 9600)
        #expect(final.notes.contains("reconcileAttemptsExhausted"))
    }

    // MARK: - Process discovery fallback

    @Test("process-only discovery stays unknown and never arms auto")
    func processFallback() throws {
        let records = try [
            ProcessRecord(
                identity: try ProcessIdentity(pid: 4242, startTime: 1_700_000_000),
                executableName: "codex", lastSeenMonotonic: 100),
            // Same PID reused by a later launch: distinct identity.
            ProcessRecord(
                identity: try ProcessIdentity(pid: 4242, startTime: 1_700_000_900),
                executableName: "codex", lastSeenMonotonic: 200),
            ProcessRecord(
                identity: try ProcessIdentity(pid: 5150, startTime: nil),
                executableName: "opencode", lastSeenMonotonic: 200),
        ]
        let discovery = ProcessDiscovery(
            provider: InMemoryProcessList(records: records),
            patterns: [
                CandidatePattern(executableContains: "codex", provider: "codex"),
                CandidatePattern(executableContains: "opencode", provider: "opencode"),
            ])
        let candidates = discovery.discover()
        #expect(candidates.count == 3)
        #expect(Set(candidates.map(\.identity)).count == 3)
        #expect(!ProcessDiscovery.canArmAuto(kind: .process))
        #expect(ProcessDiscovery.canArmAuto(kind: .lifecycle))
        #expect(ProcessDiscovery.rank(kind: .lifecycle) > ProcessDiscovery.rank(kind: .wrapper))
        #expect(ProcessDiscovery.rank(kind: .wrapper) > ProcessDiscovery.rank(kind: .process))
        let events = discovery.normalizedEvents(sessionID: "s-proc", receivedMonotonic: 300)
        #expect(!events.isEmpty)
        for event in events {
            #expect(event.state == .unknown)
            #expect(event.evidenceKind == .process)
            #expect(event.confidence != .exact)
        }
        var normalizer = EvidenceNormalizer()
        for event in events {
            let task = try appliedTask(normalizer.normalize(event))
            // Process-only evidence never completes and never claims work.
            #expect(task.state != .completed)
            #expect(task.state != .working)
        }
    }

    // MARK: - Installer preview/install/removal

    @Test("installer preserves unknown keys and restores on removal")
    func installerRoundTrip() throws {
        let files = InMemoryConfigFileSystem(files: [
            "~/.claude/settings.json": #"{"userHook":true,"hooks":{"Stop":[]}}"#,
            "~/.codex/camlid-hooks.json": "orca:managed legacy hooks",
        ])
        let installer = IntegrationInstaller(filesystem: files)
        let preview = try installer.preview(descriptors: [.claude, .codex, .orca])
        #expect(preview.contains { $0.path == "~/.claude/settings.json" && $0.action == .mergeJSON })
        #expect(preview.contains {
            $0.path == "~/.codex/camlid-hooks.json" && $0.action == .skipOrcaManaged
        })
        // Orca contributes no writes: externally managed.
        #expect(!preview.contains { $0.path.contains("orca") })
        let applied = try installer.install(descriptors: [.claude, .codex])
        #expect(applied.contains {
            $0.path == "~/.claude/settings.json" && $0.backupPath == "~/.claude/settings.json.camlid-backup"
        })
        let installed = try files.readFile(at: "~/.claude/settings.json")
        #expect(installed?.contains("\"userHook\"") == true)
        #expect(installed?.contains("camlid:owned:claude:v1") == true)
        // Orca-managed content untouched by install.
        #expect(try files.readFile(at: "~/.codex/camlid-hooks.json") == "orca:managed legacy hooks")
        let removed = try installer.remove(descriptors: [.claude, .codex])
        #expect(removed.contains {
            $0.path == "~/.claude/settings.json" && $0.action == .restoredBackup
        })
        #expect(try files.readFile(at: "~/.claude/settings.json")
            == #"{"userHook":true,"hooks":{"Stop":[]}}"#)
    }

    @Test("installer removes only owned markers without a backup")
    func installerRemovesOwnedOnly() throws {
        let files = InMemoryConfigFileSystem()
        let installer = IntegrationInstaller(filesystem: files)
        _ = try installer.install(descriptors: [.opencode])
        let content = try files.readFile(at: "~/.config/opencode/camlid.json")
        #expect(content?.contains("camlid:owned:opencode:v1") == true)
        let removed = try installer.remove(descriptors: [.opencode])
        #expect(removed == [RemovedEntry(
            path: "~/.config/opencode/camlid.json", action: .removedOwned, backupPath: nil)])
        // Unowned content is never removed.
        try files.writeFile(at: "~/.config/opencode/camlid.json", content: #"{"user":1}"#)
        let second = try installer.remove(descriptors: [.opencode])
        #expect(second == [RemovedEntry(
            path: "~/.config/opencode/camlid.json", action: .leftUnowned, backupPath: nil)])
        #expect(try files.readFile(at: "~/.config/opencode/camlid.json") == #"{"user":1}"#)
    }
}
