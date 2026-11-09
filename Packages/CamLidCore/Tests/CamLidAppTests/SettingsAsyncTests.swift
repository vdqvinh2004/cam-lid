import Foundation
import AppKit
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

private final class PreferenceWriterSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var written: Bool { lock.withLock { value } }
    func markWritten() { lock.withLock { value = true } }
}

@Suite("Pending preference settlement", .serialized)
struct SettingsAsyncTests {
    @Test @MainActor func slowResponseCannotEraseNewerCustomInput() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var values: [Int] = []
        var current = try Configuration(); var revision = 1
        editor.configureAsyncAutosave { patch, _ in
            try? await Task.sleep(for: .milliseconds(180))
            values.append(patch.completionDelayMinutes!)
            current = try! current.applying(patch); revision += 1
            editor.receive(configuration: current, revision: revision)
            return .saved(revision: revision)
        }
        editor.selectPreset(5, field: .completionDelay)
        try await Task.sleep(for: .milliseconds(30))
        editor.editNumber("7", field: .completionDelay)
        try await Task.sleep(for: .milliseconds(190))
        #expect(editor.numbers[.completionDelay] == "7" && editor.isDirty)
        #expect(await editor.settle())
        #expect(values == [5, 7] && current.completionDelayMinutes == 7)
    }
    @Test @MainActor func rapidPresetsSerializeAndCoalesce() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        var values: [Int] = []; var revision = 1
        editor.configureAsyncAutosave { patch, expected in
            #expect(expected == revision)
            try? await Task.sleep(for: .milliseconds(80))
            values.append(patch.completionDelayMinutes!); revision += 1
            return .saved(revision: revision)
        }
        editor.selectPreset(1, field: .completionDelay)
        editor.selectPreset(5, field: .completionDelay)
        editor.selectPreset(10, field: .completionDelay)
        #expect(await editor.settle())
        #expect(values == [10] && editor.numbers[.completionDelay] == "10")
    }
    @Test @MainActor func failedWriteRemainsUnappliedAndPendingShows() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        editor.configureAsyncAutosave { _, _ in
            try? await Task.sleep(for: .milliseconds(220)); return .failed("Storage unavailable")
        }
        editor.selectPreset(5, field: .completionDelay)
        try await Task.sleep(for: .milliseconds(180))
        #expect(editor.hasPendingWrites && editor.fieldMessages["completionDelayMinutes"] == "Applying…")
        #expect(!(await editor.settle()))
        #expect(editor.isDirty && editor.message == "Storage unavailable" && editor.revision == 1)
    }
    @Test @MainActor func settlementBoundDoesNotBlockMainActor() async throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        editor.configureAsyncAutosave { _, _ in
            try? await Task.sleep(for: .milliseconds(150)); return .failed("Storage unavailable")
        }
        editor.selectPreset(5, field: .completionDelay)
        let start = ContinuousClock.now
        #expect(!(await editor.settle(timeout: .milliseconds(20))))
        #expect(start.duration(to: .now) < .milliseconds(100))
        editor.discard(); _ = await editor.settle()
        #expect(!editor.isDirty && editor.numbers[.completionDelay] == "2")
    }
    @Test @MainActor func timedOutWorkerCannotInstallLateFileOrQueueMoreWorkers() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let releaseWriter = DispatchSemaphore(value: 0), fileWritten = PreferenceWriterSignal()
        defer { releaseWriter.signal() }
        let writer: @Sendable (Data, URL) throws -> Void = { data, url in
            releaseWriter.wait()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            fileWritten.markWritten()
        }
        let app = AppCoordinator(historyDirectory: fixture.root.appendingPathComponent("history"),
            controlDirectory: fixture.root.appendingPathComponent("control"), preferences: fixture.preferences, settingsWriter: writer)
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        if case .failed = await app.applySettingsPatchAsync(patch, expectedRevision: 1, deadline: ContinuousTime.now + 0.03) {} else { Issue.record("Expected timeout") }
        if case .failed = await app.applySettingsPatchAsync(patch, expectedRevision: 1) {} else { Issue.record("Expected busy worker refusal") }
        releaseWriter.signal()
        let end = ContinuousClock.now + .milliseconds(250)
        var written = false, cleaned = false
        repeat {
            if !written { written = fileWritten.written }
            if written {
                cleaned = (try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("history").path)).allSatisfy { !$0.hasPrefix(".candidate-") }
            }
            if written && cleaned { break }
            try await Task.sleep(for: .milliseconds(1))
        } while ContinuousClock.now < end
        #expect(written && cleaned)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("history/preferences.json").path))
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.configGet, payload: Data()))
        #expect(reply.json.contains("\"revision\":1") && reply.json.contains("\"completionDelayMinutes\":2"))
        #expect((try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("history").path)).allSatisfy { !$0.hasPrefix(".candidate-") })
    }
    @Test @MainActor func concurrentAuthorityEditRejectsPreparedStaleRevision() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let writer: @Sendable (Data, URL) throws -> Void = { data, url in
            Thread.sleep(forTimeInterval: 0.04)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let app = AppCoordinator(historyDirectory: fixture.root.appendingPathComponent("history"), preferences: fixture.preferences, settingsWriter: writer)
        var first = ConfigPatch(); first.completionDelayMinutes = 7
        let pending = Task { await app.applySettingsPatchAsync(first, expectedRevision: 1) }
        try await Task.sleep(for: .milliseconds(5))
        var external = ConfigPatch(); external.runCapMinutes = 30
        guard case .saved = app.applySettingsPatch(external, expectedRevision: 1) else { Issue.record("Expected concurrent save"); return }
        guard case .conflict(let config, let revision) = await pending.value else { Issue.record("Expected stale revision refusal"); return }
        #expect(config.completionDelayMinutes == 2 && config.runCapMinutes == 30 && revision == 2)
        let restored = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: restored.handleControl(.configGet, payload: Data()))
        #expect(reply.json.contains("\"completionDelayMinutes\":2") && reply.json.contains("\"runCapMinutes\":30"))
    }
    @Test @MainActor func duplicateInstanceCannotOverwriteAuthorityPreferences() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let owner = fixture.makeCoordinator(); owner.startControlService()
        defer { owner.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let duplicate = fixture.makeCoordinator(); duplicate.startControlService()
        defer { duplicate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        var first = ConfigPatch(); first.completionDelayMinutes = 7
        guard case .saved = await owner.applySettingsPatchAsync(first, expectedRevision: 1) else { Issue.record("Expected owner save"); return }
        var second = ConfigPatch(); second.runCapMinutes = 30
        guard case .failed = await duplicate.applySettingsPatchAsync(second, expectedRevision: 1) else { Issue.record("Expected duplicate refusal"); return }
        guard case .failed = duplicate.applySettingsPatch(second, expectedRevision: 1) else { Issue.record("Expected sync duplicate refusal"); return }
        #expect(await owner.flushHistory())
        #expect(await duplicate.flushHistory())
        let records = FileHistoryStorage(directory: fixture.root.appendingPathComponent("history")).load()
        #expect(records.filter { $0.reasonCodes.contains("configApplied") }.count == 1)
        let restored = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: restored.handleControl(.configGet, payload: Data()))
        #expect(reply.json.contains("\"completionDelayMinutes\":7") && reply.json.contains("\"runCapMinutes\":120"))
    }

}
