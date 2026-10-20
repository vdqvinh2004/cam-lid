import Testing
import Foundation
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Automatic settings", .serialized)
struct SettingsAutosaveTests {
    @Test @MainActor func unrelatedConcurrentEditSurvives() throws {
        let base = try Configuration(); let editor = SettingsEditor(configuration: base, revision: 1)
        var current = base; current.runCapMinutes = 30; var revision = 2
        editor.configureAutosave { patch, expected in
            guard expected == revision else { return .conflict(configuration: current, revision: revision) }
            current = try! current.applying(patch); revision += 1; return .saved(revision: revision)
        }
        editor.selectPreset(5, field: .completionDelay)
        #expect(current.completionDelayMinutes == 5 && current.runCapMinutes == 30)
        #expect(!editor.isDirty)
    }
    @Test @MainActor func sameFieldConflictNeedsChoice() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var current = try Configuration(completionDelayMinutes: 10); var revision = 2
        editor.configureAutosave { patch, expected in
            guard expected == revision else { return .conflict(configuration: current, revision: revision) }
            current = try! current.applying(patch); revision += 1; return .saved(revision: revision)
        }
        editor.selectPreset(5, field: .completionDelay)
        #expect(current.completionDelayMinutes == 10 && editor.conflict)
        editor.applyMyValue(key: "completionDelayMinutes")
        #expect(current.completionDelayMinutes == 5 && !editor.isDirty)
    }
    @Test @MainActor func invalidCustomAndFailureNeverApply() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var calls = 0
        editor.configureAutosave { _, _ in calls += 1; return .failed("Storage unavailable") }
        editor.editNumber("", field: .completionDelay); editor.flush()
        #expect(calls == 0 && !editor.errors.isEmpty)
        #expect(editor.message?.hasPrefix("Not applied") == true)
        editor.editNumber("7", field: .completionDelay); editor.flush()
        #expect(calls == 1 && editor.isDirty && editor.message == "Storage unavailable")
        editor.discard(); #expect(!editor.isDirty && editor.numbers[.completionDelay] == "2")
    }
    @Test @MainActor func rapidCustomEditsCommitOnlyLatest() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var values: [Int] = []
        editor.configureAutosave { patch, _ in values.append(patch.completionDelayMinutes!); return .saved(revision: 2) }
        editor.editNumber("1", field: .completionDelay); editor.editNumber("12", field: .completionDelay)
        editor.flush()
        try await Task.sleep(for: .milliseconds(450))
        #expect(values == [12])
    }
    @Test @MainActor func otherProviderEnrollmentIsPreserved() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var current = try Configuration(adapterEnrollment: ["opencode"]); var revision = 2
        editor.configureAutosave { patch, expected in
            guard expected == revision else { return .conflict(configuration: current, revision: revision) }
            current = try! current.applying(patch); revision += 1; return .saved(revision: revision)
        }
        editor.setProvider("codex", enabled: true)
        #expect(Set(current.adapterEnrollment) == ["codex", "opencode"])
    }
    @Test @MainActor func lifetimeRuleEditingUsesRevisionCheckedPatchAndFullDraftPreservesRules() throws {
        let existing = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        let added = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "org.example.editor", label: "Editor")
        let base = try Configuration(lifetimeRules: [existing])
        let editor = SettingsEditor(configuration: base, revision: 1)
        var current = base; var revision = 1
        editor.configureAutosave { patch, expected in
            guard expected == revision else { return .conflict(configuration: current, revision: revision) }
            current = try! current.applying(patch); revision += 1; return .saved(revision: revision)
        }
        editor.setLifetimeRules([existing, added])
        #expect(current.lifetimeRules == [existing, added])
        #expect(revision == 2 && !editor.isDirty)
        #expect(try editor.draft.makeConfiguration().lifetimeRules == [existing, added])
        editor.setLifetimeRules([added])
        #expect(current.lifetimeRules == [added])
        #expect(revision == 3 && !editor.isDirty)
    }
    @Test @MainActor func enableAllSerializesAndPreservesUnrelatedPreferences() async throws {
        let editor = SettingsEditor(configuration: try Configuration(mode: .auto, adapterEnrollment: ["orca"]), revision: 1)
        var current = try Configuration(mode: .auto, adapterEnrollment: ["orca"])
        var revision = 1
        editor.configureAsyncAutosave { patch, expected in
            try? await Task.sleep(for: .milliseconds(10))
            guard expected == revision else { return .conflict(configuration: current, revision: revision) }
            current = try! current.applying(patch); revision += 1
            return .saved(revision: revision)
        }
        editor.enableAllProviders()
        #expect(await editor.settle())
        #expect(Set(current.adapterEnrollment) == Set(AgentBadgeState.providers))
        #expect(current.mode == .auto && current.completionDelayMinutes == 2)
        #expect(!editor.isDirty)
    }
    @Test @MainActor func realStorageFailureRetainsConfigAndRevision() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let coordinator = fixture.makeCoordinator(failingWrites: true)
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        if case .failed = coordinator.applySettingsPatch(patch, expectedRevision: 1) {} else { Issue.record("Expected storage failure") }
        let data = try coordinator.handleControl(.configGet, payload: Data())
        let reply = try JSONDecoder().decode(CLIResult.self, from: data)
        let object = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        #expect(object["revision"] as? Int == 1)
        #expect(object["completionDelayMinutes"] as? Int == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("history/preferences.json").path))
    }

    @Test @MainActor func composingInputNeverCommitsUntilCompositionEnds() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var calls = 0
        editor.configureAutosave { _, _ in calls += 1; return .saved(revision: 2) }
        editor.editNumber("7", field: .completionDelay, composing: true); editor.flush()
        #expect(calls == 0 && editor.isDirty)
        editor.editNumber("7", field: .completionDelay); editor.flush()
        #expect(calls == 1 && !editor.isDirty)
    }
    @Test @MainActor func filePreferenceRestartRetainsCustomAndRevision() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let coordinator = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        guard case .saved(let revision) = coordinator.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Expected persisted patch"); return
        }
        let restored = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: restored.handleControl(.configGet, payload: Data()))
        let object = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        #expect(object["completionDelayMinutes"] as? Int == 7 && object["revision"] as? Int == revision)
        let editor = SettingsEditor(configuration: try Configuration(completionDelayMinutes: 7), revision: revision)
        #expect(editor.customFields.contains(.completionDelay))
    }
    @Test @MainActor func retryIsBoundedAndKeepsNewerInput() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var attempts = 0
        editor.configureAutosave { _, revision in
            attempts += 1; return .conflict(configuration: try! Configuration(runCapMinutes: 30), revision: revision + 1)
        }
        editor.selectPreset(5, field: .completionDelay)
        #expect(attempts == 2 && editor.isDirty && editor.conflict)
        editor.useCurrent(key: "completionDelayMinutes")
        #expect(!editor.isDirty && editor.numbers[.runCap] == "30")
    }
    @Test @MainActor func liveReadbackRefreshesCleanFieldsWithoutOverwritingPendingConflict() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        editor.editNumber("7", field: .completionDelay)
        var current = try Configuration(completionDelayMinutes: 10, runCapMinutes: 30)
        var revision = 2; var writes = 0
        editor.configureAutosave { patch, expected in
            #expect(expected == revision); writes += 1
            current = try! current.applying(patch); revision += 1; return .saved(revision: revision)
        }
        editor.receive(configuration: current, revision: revision)
        #expect(editor.numbers[.completionDelay] == "7" && editor.numbers[.runCap] == "30")
        editor.flush()
        #expect(writes == 0 && editor.conflict)
        editor.applyMyValue(key: "completionDelayMinutes")
        #expect(writes == 1 && current.completionDelayMinutes == 7 && !editor.isDirty)
    }
}
