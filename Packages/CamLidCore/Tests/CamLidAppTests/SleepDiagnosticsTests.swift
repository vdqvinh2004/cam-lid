import Testing
import Foundation
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Sleep diagnostics and display preference", .serialized)
struct SleepDiagnosticsTests {
    @Test func hungCollectionTimesOutWithoutStartingAnotherWorker() async {
        let release = DispatchSemaphore(value: 0)
        let reader = SleepDiagnosticReader(timeout: 0.02, nativeReader: {
            release.wait(); return SleepDiagnosticsSnapshot()
        }, powerReader: { DiagnosticSnapshot() })
        defer { release.signal() }
        let timedOut = await reader.snapshot()
        #expect(timedOut.errors == ["collectionTimedOut"] && !timedOut.hasCoverage)
        let busy = await reader.snapshot()
        #expect(busy.errors == ["collectionBusy"])
    }
    @Test func collectorBoundsRowsAndKeepsUnknownEffectExplicit() async {
        let rows = (0..<300).map { SleepAssertion(id: String($0), pid: 42, owner: "Local owner",
            type: "FutureAssertion", reason: "PRIVATE_REASON") }
        let reader = SleepDiagnosticReader(timeout: 1, nativeReader: { SleepDiagnosticsSnapshot(assertions: rows) },
            powerReader: { throw IPCError.unavailable })
        let result = await reader.snapshot()
        #expect(result.blockers.count == 256 && result.coverage["userAssertions"] == .partial)
        #expect(result.errors.contains("powerCategoriesUnavailable"))
        #expect(result.blockers.allSatisfy { $0.effect == .unknown })
        #expect(!String(describing: result).contains("PRIVATE_REASON"))
    }
    @Test func globalAndKernelParsingNeverExportsRawLabels() throws {
        #expect(throws: OrcaPollError.self) {
            try OrcaPoller.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["over-budget"], maximumBytes: 4)
        }
        let parsed = SleepDiagnosticReader.powerCategories(settings: "System-wide power settings:\n SleepDisabled 1\n",
            assertions: "Kernel Assertions: 0x4=USB\n description=PRIVATE_DEVICE owner=PRIVATE_OWNER")
        #expect(parsed.coverage["global"] == .complete && parsed.coverage["kernel"] == .complete)
        #expect(parsed.blockers.map(\.effect) == [.global, .kernel])
        #expect(!String(describing: parsed).contains("PRIVATE"))
        let unknown = SleepDiagnosticReader.powerCategories(settings: "new format", assertions: "new format")
        #expect(unknown.coverage.values.allSatisfy { $0 == .unavailable })
        let none = SleepDiagnosticReader.powerCategories(settings: " SleepDisabled 0", assertions: "Kernel Assertions: None")
        #expect(none.blockers.isEmpty && none.hasCoverage)
        let zeroFlags = SleepDiagnosticReader.powerCategories(settings: " SleepDisabled 0", assertions: "Kernel Assertions: 0x0=0")
        #expect(zeroFlags.coverage["kernel"] == .complete && zeroFlags.blockers.isEmpty)
    }
    @Test @MainActor func savedModeIsNotAnActiveSessionAndDiagnosisUsesSameSnapshot() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.mode = .timed
        _ = app.applySettingsPatch(patch, expectedRevision: 1)
        let data = try app.handleControl(.status, payload: Data())
        let reply = try JSONDecoder().decode(CLIResult.self, from: data)
        let json = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        #expect(json["configuredMode"] as? String == "timed")
        #expect(json["activeSessionMode"] is NSNull)
        #expect(json["powerActuation"] as? Bool == false)
    }

    @Test func backgroundAndPushAssertionsMapToSystemIdle() {
        #expect(SleepEffect.assertion("BackgroundTask") == .systemIdle)
        #expect(SleepEffect.assertion("ApplePushServiceTask") == .systemIdle)
        #expect(SleepEffect.assertion("NetworkClientActive") == .systemIdle)
        #expect(SleepEffect.assertion("SystemIsActive") == .systemIdle)
        #expect(SleepEffect.assertion("InternalPreventDisplaySleep") == .displayIdle)
        #expect(SleepEffect.assertion("PreventUserIdleDisplaySleep") == .displayIdle)
        #expect(SleepEffect.assertion("UserIsActive") == .userActivity)
        #expect(SleepEffect.assertion("FutureAssertion") == .unknown)
    }

    @Test func backgroundTasksAreProjectedWhenSystemActive() {
        let rows = SleepDiagnosticsSnapshot.project(processes: [9: [
            ["AssertLevel": 255, "AssertType": "BackgroundTask", "AssertionId": 1, "Process Name": "dasd"],
            ["AssertLevel": 255, "AssertType": "ApplePushServiceTask", "AssertionId": 2, "Process Name": "apsd"],
        ]], status: ["BackgroundTask": 1, "ApplePushServiceTask": 1])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { SleepEffect.assertion($0.type) == .systemIdle })
    }

    @Test func preventingLineIsParsedDedupedAndRedacted() throws {
        let parsed = SleepDiagnosticReader.powerCategories(
            settings: "System-wide power settings:\n SleepDisabled 0\n sleep 1 (sleep prevented by dasd, nsurlsessiond, dasd, FaceTime)",
            assertions: "Kernel Assertions: None")
        #expect(parsed.coverage["preventing"] == .complete)
        #expect(parsed.preventedBy == ["dasd", "nsurlsessiond", "FaceTime"])
        #expect(parsed.coverage["global"] == .complete)
        #expect(!String(describing: parsed.redacted()).contains("FaceTime"))

        let idle = SleepDiagnosticReader.powerCategories(settings: " SleepDisabled 0\n sleep 1",
            assertions: "Kernel Assertions: None")
        #expect(idle.preventedBy.isEmpty && idle.coverage["preventing"] == .complete)

        let unavailable = SleepDiagnosticReader.powerCategories(settings: "new format", assertions: "new format")
        #expect(unavailable.coverage["preventing"] == .unavailable)

        let snapshot = DiagnosticSnapshot(blockers: [
            DiagnosticBlocker(id: "1", type: "BackgroundTask", effect: .systemIdle, source: "IOKit",
                owner: "dasd", pid: 42, explanation: "Keeps system awake"),
        ], preventedBy: ["dasd"])
        #expect(snapshot.redacted().preventedBy.isEmpty)
        #expect(snapshot.redacted().blockers.first?.owner == nil)

        let encoded = try JSONEncoder().encode(DiagnosticSnapshot())
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "preventedBy")
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DiagnosticSnapshot.self, from: older).preventedBy.isEmpty)
    }

    @Test func activeRequestsDistinguishSystemDisplayAndUserActivity() {
        let entries: [[String: Any]] = [
            ["AssertLevel": 255, "AssertType": "UserIsActive", "AssertionId": 1],
            ["AssertLevel": 255, "AssertType": "PreventUserIdleSystemSleep", "AssertionId": 2, "Process Name": "worker", "AssertName": "Job", "HumanReadableReason": "Running job"],
            ["AssertLevel": 255, "AssertType": "PreventUserIdleDisplaySleep", "AssertionId": 3],
            ["AssertLevel": 255, "AssertType": "PreventSystemSleep", "AssertionId": 4],
            ["AssertLevel": 0, "AssertType": "PreventUserIdleSystemSleep", "AssertionId": 5],
            ["AssertType": "PreventUserIdleSystemSleep", "AssertionId": 6],
            ["AssertLevel": 255, "AssertType": "UnknownFutureType", "AssertionId": 7],
        ]
        let rows = SleepDiagnosticsSnapshot.project(processes: [42: entries], status: [
            "UserIsActive": 1, "PreventUserIdleSystemSleep": 1, "PreventUserIdleDisplaySleep": 1,
            "PreventSystemSleep": 0, "UnknownFutureType": 1,
        ])
        #expect(rows.count == 4 && Set(rows.map(\.id)).count == 4)
        #expect(rows.filter(\.holdsSystemSleep).count == 2 && rows.filter(\.holdsDisplaySleep).count == 1)
        #expect(rows.first?.holdsSystemSleep == true)
        #expect(rows.first { $0.type == "UserIsActive" }?.holdsSystemSleep == false)
        #expect(rows.allSatisfy { $0.type != "PreventSystemSleep" })
        #expect(rows.first { $0.type == "UnknownFutureType" }?.effect == "Other power activity")
        #expect(rows.first { $0.owner == "worker" }?.reason == "Job\nRunning job")
        #expect(SleepDiagnosticsSnapshot.project(processes: [:], status: [:]).isEmpty)
    }

    @Test func olderPreferencesAndStrictBooleanPatches() throws {
        let old = try Configuration(mode: .auto, runCapMinutes: 30)
        // The old encoding lacks the new optional key; decoding preserves all fields.
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("allowDisplaySleep"))
        let restored = try JSONDecoder().decode(Configuration.self, from: data)
        #expect(restored == old && restored.displaySleepAllowed)
        let patch = try ConfigPatch(jsonDictionary: ["allowDisplaySleep": false])
        let next = try restored.applying(patch)
        #expect(!next.displaySleepAllowed && next.mode == .auto && next.runCapMinutes == 30)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(next)) == next)
        for invalid: Any in [NSNull(), NSNumber(value: 1), "false"] {
            #expect(throws: ConfigError.invalidType(key: "allowDisplaySleep")) {
                try ConfigPatch(jsonDictionary: ["allowDisplaySleep": invalid])
            }
        }
    }

    @Test @MainActor func displayPreferenceAutosavesRetriesAndSurvivesRestartWithoutArming() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let coordinator = fixture.makeCoordinator()
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var current = try Configuration(runCapMinutes: 30)
        var revision = 2
        editor.configureAutosave { patch, expected in
            guard expected == revision else { return .conflict(configuration: current, revision: revision) }
            current = try! current.applying(patch); revision += 1; return .saved(revision: revision)
        }
        editor.setAllowDisplaySleep(false)
        #expect(!current.displaySleepAllowed && current.runCapMinutes == 30 && !editor.isDirty)
        #expect(try editor.draft.makeConfiguration().allowDisplaySleep == false)
        var patch = ConfigPatch(); patch.allowDisplaySleep = false
        guard case .saved(let persistedRevision) = coordinator.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Display preference did not persist"); return
        }
        let restored = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: restored.handleControl(.configGet, payload: Data()))
        let object = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        #expect(object["allowDisplaySleep"] as? Bool == false)
        #expect(object["revision"] as? Int == persistedRevision && object["mode"] as? String == "off")
    }

    @Test @MainActor func failedDisplayEditKeepsDraftAndOtherReadbackFields() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        editor.configureAutosave { _, _ in .failed("Storage unavailable") }
        editor.setAllowDisplaySleep(false)
        editor.receive(configuration: try Configuration(runCapMinutes: 30), revision: 2)
        #expect(editor.draft.allowDisplaySleep == false && editor.numbers[.runCap] == "30")
        #expect(editor.isDirty && editor.fieldMessages["allowDisplaySleep"] == "Storage unavailable")
        editor.useCurrent(key: "allowDisplaySleep")
        #expect(editor.draft.allowDisplaySleep == nil && !editor.isDirty)
    }
}
