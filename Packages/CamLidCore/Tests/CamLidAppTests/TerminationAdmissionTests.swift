import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

struct TerminationAdmissionTests {
    @Test @MainActor func onboardingContinuationCannotPersistOrRecordAfterQuitStarts() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let preferences = fixture.preferences
        #expect(app.beginTerminationFlow())
        app.sealTerminationHistory()
        #expect(!app.finishOnboarding())
        #expect(!preferences.bool(forKey: "CamLidOnboarded"))
        #expect(await app.flushHistory())
        #expect(FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load().isEmpty)
        app.cancelTerminationFlow()
        #expect(app.finishOnboarding())
        #expect(preferences.bool(forKey: "CamLidOnboarded"))
        #expect(await app.flushHistory())
        #expect(FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load().filter { $0.reasonCodes.contains("onboardingComplete") }.count == 1)
    }

    @Test @MainActor func stagingAdmittedBeforeQuitCannotInstallAfterQuitStarts() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = AppCoordinator(historyDirectory: fixture.root.appendingPathComponent("history"),
            preferences: fixture.preferences, settingsWriter: { data, url in
                Thread.sleep(forTimeInterval: 0.1)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            })
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        let pending = Task { await app.applySettingsPatchAsync(patch, expectedRevision: 1) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(app.beginTerminationFlow())
        #expect(await app.settleSettingsInstallation())
        app.sealTerminationHistory()
        guard case .failed = await pending.value else { Issue.record("Staging passed quit admission"); return }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("history/preferences.json").path))
        app.cancelTerminationFlow()
        #expect(await app.flushHistory())
    }

    @Test @MainActor func quitRejectsNewMutationsKeepsReadbackAndCancellationRestoresAdmission() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        #expect(app.beginTerminationFlow())
        #expect(!app.beginTerminationFlow())
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        guard case .failed = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else { Issue.record("Write admitted during quit"); return }
        #expect(throws: IPCError.policyDenied("applicationTerminating")) {
            try app.handleControl(.event, payload: Data("{}".utf8))
        }
        app.sealTerminationHistory()
        let read = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.configGet, payload: Data()))
        #expect(read.json.contains("\"revision\":1"))
        #expect(await app.flushHistory())
        app.cancelTerminationFlow()
        guard case .saved(let revision) = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else { Issue.record("Cancelled quit must restore writes"); return }
        #expect(revision == 2)
        #expect(await app.flushHistory())
        let records = FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load()
        #expect(records.filter { $0.reasonCodes.contains("configApplied") }.count == 1)
    }
}
