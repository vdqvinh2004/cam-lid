import Foundation
import Testing
import Darwin
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Unconfirmed settings installation", .serialized)
struct SettingsInstallationTests {
    @Test @MainActor func cancelledBeforeInstallationAdmissionCannotInvokeInstaller() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let destination = fixture.root.appendingPathComponent("preferences.json")
        let preparer = PreferenceWritePreparer(writer: { data, url in try data.write(to: url) },
            installer: { _, _ in Issue.record("Cancelled installation invoked installer") })
        let source = try #require(await preparer.prepare(Data("{}".utf8), beside: destination, deadline: ContinuousTime.now + 1))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await preparer.install(source, at: destination, deadline: ContinuousTime.now + 1) { _ in }
        }
        if case .failed = await cancelled.value {} else { Issue.record("Cancelled admission must fail") }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test @MainActor func confirmedFailureReplacesUncertaintyAndDiscardCannotHideStartedInstall() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        editor.configureAsyncAutosave { _, _ in .unconfirmed("Outcome unconfirmed — still finishing") }
        editor.selectPreset(5, field: .completionDelay)
        #expect(!(await editor.settle()))
        editor.installationPending = true
        editor.discard()
        #expect(editor.isDirty && editor.hasPendingWrites)
        #expect(editor.message?.contains("may apply later") == true)
        editor.installationFinished(success: false)
        #expect(!editor.isDirty && editor.message?.hasPrefix("Not applied") == true)
        editor.selectPreset(10, field: .completionDelay)
        #expect(!(await editor.settle()))
        editor.installationFinished(success: false)
        #expect(editor.fieldMessages["completionDelayMinutes"]?.hasPrefix("Not applied") == true)
    }

    @Test @MainActor func lateInstallationIsUnconfirmedSerializedAndReconciledOnce() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = AppCoordinator(historyDirectory: fixture.root.appendingPathComponent("history"),
            preferences: fixture.preferences, settingsInstaller: { source, destination in
                Thread.sleep(forTimeInterval: 0.18)
                guard Darwin.rename(source.path, destination.path) == 0 else { throw POSIXError(.EIO) }
            })
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        let started = ContinuousClock.now
        guard case .unconfirmed = await app.applySettingsPatchAsync(patch, expectedRevision: 1,
            deadline: ContinuousTime.now + 0.04) else { Issue.record("Expected unconfirmed installation"); return }
        #expect(started.duration(to: .now) < .milliseconds(130))
        #expect(app.hasPendingSettingsInstallation)
        var other = ConfigPatch(); other.runCapMinutes = 30
        guard case .unconfirmed = await app.applySettingsPatchAsync(other, expectedRevision: 1) else { Issue.record("Expected serialized refusal"); return }
        guard case .failed = app.applySettingsPatch(other, expectedRevision: 1) else { Issue.record("Compatibility writer must refuse too"); return }
        #expect(!(await app.settleSettingsInstallation(timeout: 0.01)))
        #expect(await app.settleSettingsInstallation())
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.configGet, payload: Data()))
        #expect(reply.json.contains("\"revision\":2") && reply.json.contains("\"completionDelayMinutes\":7"))
        #expect(reply.json.contains("\"runCapMinutes\":120"))
        #expect(await app.flushHistory())
        let records = FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load()
        #expect(records.filter { $0.reasonCodes.contains("configApplied") }.count == 1)
        #expect(records.filter { $0.reasonCodes.contains("configCommitUnconfirmed") }.count == 1)
    }

    @Test @MainActor func controlTimeoutReportsReadBackRequiredAndLateFailureRetainsRevision() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = AppCoordinator(historyDirectory: fixture.root.appendingPathComponent("history"),
            preferences: fixture.preferences, settingsInstaller: { _, _ in
                Thread.sleep(forTimeInterval: 0.15); throw POSIXError(.EIO)
            })
        let options = CLIOptions(flags: ["patchJSON": "{\"completionDelayMinutes\":7}"])
        let data = try await app.handleControlAsync(.configSet, payload: JSONEncoder().encode(options),
            deadline: ContinuousTime.now + 0.04)
        let response = try JSONDecoder().decode(CLIResult.self, from: data)
        #expect(response.exitCode == 5 && response.json.contains("commitUnconfirmed"))
        #expect(response.json.contains("\"mayApplyLater\":true") && response.json.contains("\"readBackRequired\":true"))
        #expect(await app.settleSettingsInstallation())
        let saved = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.configGet, payload: Data()))
        #expect(saved.json.contains("\"revision\":1") && saved.json.contains("\"completionDelayMinutes\":2"))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("history/preferences.json").path))
        #expect(await app.flushHistory())
    }

    @Test @MainActor func lateConfirmedValueClearsOnlyMatchingUnconfirmedInput() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        editor.configureAsyncAutosave { _, _ in .unconfirmed("Outcome unconfirmed — storage is still finishing") }
        editor.selectPreset(5, field: .completionDelay)
        #expect(!(await editor.settle()))
        #expect(editor.isDirty)
        var matching = try Configuration(); matching.completionDelayMinutes = 5
        editor.receive(configuration: matching, revision: 2)
        #expect(!editor.isDirty && editor.message == "Applied")
        editor.selectPreset(10, field: .completionDelay)
        #expect(!(await editor.settle()))
        var unrelated = matching; unrelated.runCapMinutes = 30
        editor.receive(configuration: unrelated, revision: 3)
        #expect(editor.isDirty && editor.numbers[.completionDelay] == "10")
    }
}
