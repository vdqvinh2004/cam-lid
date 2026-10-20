import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Preference changes preserve protection boundaries", .serialized)
struct PreferenceDeadlineTests {
    @Test func explicitTimerEditsRestartNowAndCannotClearSafetyOrExpiry() throws {
        var session = try ProtectionSession(id: "timer", requestedMode: .timed, armedClosedLid: false,
            startedAtMonotonic: 10, capDeadlineMonotonic: 1810)
        #expect(session.restartTimer(minutes: 5, maximumMinutes: 120, now: 100) == 5)
        #expect(session.capDeadlineMonotonic == 400 && session.startedAtMonotonic == 10)
        #expect(session.restartTimer(minutes: 1, maximumMinutes: 120, now: 110) == nil)
        #expect(session.capDeadlineMonotonic == 400)
        #expect(session.restartTimer(minutes: 0, maximumMinutes: 120, now: 120) == 0)
        #expect(session.capDeadlineMonotonic == nil)
        #expect(session.restartTimer(minutes: 480, maximumMinutes: 30, now: 130) == 30)
        #expect(session.capDeadlineMonotonic == 1930)
        session.latchedSafetyStop = true
        #expect(session.restartTimer(minutes: 0, maximumMinutes: 120, now: 140) == nil)
        #expect(session.capDeadlineMonotonic == 1930)
        session.latchedSafetyStop = false; session.effectiveState = .expired
        #expect(session.restartTimer(minutes: 0, maximumMinutes: 120, now: 150) == nil)
        session.effectiveState = .protected
        #expect(session.restartTimer(minutes: 0, maximumMinutes: 120, now: 1930) == nil)
        #expect(session.capDeadlineMonotonic == 1930)
    }

    @Test func explicitSleepDelayEditsRemainMeasuredFromCompletion() throws {
        var session = try ProtectionSession(id: "auto", requestedMode: .auto, armedClosedLid: false,
            startedAtMonotonic: 0, capDeadlineMonotonic: 7200)
        session.effectiveState = .completionGrace; session.graceDeadlineMonotonic = 130
        let extended = session.changeSleepDelay(minutes: 7, previousMinutes: 2)
        #expect(extended)
        #expect(session.graceDeadlineMonotonic == 430 && session.capDeadlineMonotonic == 7200)
        let invalid = session.changeSleepDelay(minutes: 31, previousMinutes: 7)
        #expect(!invalid)
        let immediate = session.changeSleepDelay(minutes: 0, previousMinutes: 7)
        #expect(immediate)
        #expect(session.graceDeadlineMonotonic == 10)
        session.latchedSafetyStop = true
        let latched = session.changeSleepDelay(minutes: 30, previousMinutes: 0)
        #expect(!latched)
    }

    @Test @MainActor func appliedPreferencesPreserveExistingCapAndNeverArmClosedLid() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        app.changeMode(.timed)
        await app.startPreviewSession()
        let selectedDuration = app.dashboardData().timerMinutes
        let selectedDelay = app.dashboardData().sleepDelayMinutes
        func status() throws -> [String: Any] {
            let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
            return try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        }
        let initial = try status()
        let first = try #require(initial["session"] as? [String: Any])
        var patch = ConfigPatch(); patch.runCapMinutes = 480; patch.timerMinutes = 30; patch.completionDelayMinutes = 30
        patch.waitRetentionMinutes = 30; patch.closedLidOptIn = true; patch.adapterEnrollment = ["codex"]
        let revision = try #require(initial["revision"] as? Int)
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: revision) else { Issue.record("Expected preference save"); return }
        let latest = try status(); let session = try #require(latest["session"] as? [String: Any])
        #expect(session["id"] as? String == first["id"] as? String)
        #expect(session["capDeadlineMonotonic"] as? Double == first["capDeadlineMonotonic"] as? Double)
        #expect(session["armedClosedLid"] as? Bool == false)
        #expect(app.dashboardData().timerMinutes == selectedDuration)
        #expect(app.dashboardData().sleepDelayMinutes == selectedDelay)
        #expect(latest["powerActuation"] as? Bool == false && latest["leaseVerified"] as? Bool == false)
        #expect(await app.flushHistory())
    }

    @Test @MainActor func authorityLogsEachAppliedConflictAndFailedAttemptOnce() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else { Issue.record("Expected save"); return }
        guard case .conflict = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else { Issue.record("Expected conflict"); return }
        #expect(await app.flushHistory())
        let records = FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load()
        #expect(records.filter { $0.reasonCodes.contains("configApplied") }.count == 1)
        #expect(records.filter { $0.reasonCodes.contains("configConflict") }.count == 1)
        let failedFixture = QARefinementSupport(); defer { failedFixture.cleanup() }
        let failed = failedFixture.makeCoordinator(failingWrites: true)
        guard case .failed = await failed.applySettingsPatchAsync(patch, expectedRevision: 1) else { Issue.record("Expected failure"); return }
        #expect(await failed.flushHistory())
        let failures = FileHistoryStorage(directory: failedFixture.root.appendingPathComponent("history")).load()
        #expect(failures.filter { $0.reasonCodes.contains("configWriteFailed") }.count == 1)
    }

    @Test func changedCompletionPreferenceDoesNotExtendExistingGrace() throws {
        let health = try HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal,
            lidState: .closed, internalDisplayState: .asleep, capabilityVerified: true)
        var session = try ProtectionSession(id: "grace", requestedMode: .auto, armedClosedLid: true,
            startedAtMonotonic: 0, capDeadlineMonotonic: 600)
        session.effectiveState = .protected
        let first = PolicyEngine.evaluate(session: session, tasks: [], health: health, config: try Configuration(completionDelayMinutes: 2),
            armed: true, safety: .clear, recoveryConflict: false, nowMonotonic: 10)
        let changed = PolicyEngine.evaluate(session: first.session, tasks: [], health: health, config: try Configuration(completionDelayMinutes: 30),
            armed: true, safety: .clear, recoveryConflict: false, nowMonotonic: 20)
        #expect(first.session.graceDeadlineMonotonic == 130 && changed.session.graceDeadlineMonotonic == 130)
        #expect(changed.session.capDeadlineMonotonic == 600)
    }

    @Test func changedWaitPreferenceAppliesToNextTransitionOnly() throws {
        var runtime = RuntimeAgentStore()
        func event(_ state: TaskState, _ sequence: Int) throws -> Data {
            try JSONEncoder().encode(NormalizedEvent(provider: "codex", sessionID: "wait", runID: "turn", state: state,
                evidenceKind: .lifecycle, confidence: .exact, sequence: sequence, epoch: 0, receivedMonotonic: 0))
        }
        _ = try runtime.ingest(event(.working, 0), now: 0)
        _ = try runtime.ingest(event(.waiting, 1), now: 10)
        let deadline = try #require(runtime.tasks(now: 10).first?.waitUntilMonotonic)
        runtime.configure(waitRetentionSeconds: 1_800)
        _ = try runtime.ingest(event(.waiting, 2), now: 20)
        #expect(runtime.tasks(now: 20).first?.waitUntilMonotonic == deadline)
        _ = try runtime.ingest(event(.working, 3), now: 30)
        _ = try runtime.ingest(event(.waiting, 4), now: 40)
        #expect(runtime.tasks(now: 40).first?.waitUntilMonotonic == 1_840)
    }
}
