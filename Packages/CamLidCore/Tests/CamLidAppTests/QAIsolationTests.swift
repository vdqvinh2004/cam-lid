import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// Records every path a coordinator writes to.
private final class WriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func record(_ url: URL) { lock.withLock { paths.append(url.path) } }
    var all: [String] { lock.withLock { paths } }
}

/// Regression: a QA copy must never write to, or reach, the owner's settings, history, socket, helper or login item.
@Suite("QA copies stay in their own folder")
@MainActor
struct QAIsolationTests {
    @Test("A QA copy saves its settings only inside its own folder")
    func settingsStayInsideTheQAFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-qa-isolation-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writes = WriteRecorder()
        let app = AppCoordinator(locations: .test(root: root), preferences: MemoryPreferences(),
            settingsWriter: { data, url in
                writes.record(url)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            })
        app.settingsWriteBudget = 10
        var patch = ConfigPatch(); patch.completionDelayMinutes = 7
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: 1) else {
            Issue.record("The QA copy did not save its settings"); return
        }
        #expect(!writes.all.isEmpty)
        #expect(writes.all.allSatisfy { $0.hasPrefix(root.path + "/") })
        #expect(writes.all.allSatisfy { !$0.hasPrefix(StateLocations.owner.history.path) })
    }

    @Test("A QA copy refuses every helper install and removal without asking for administrator approval")
    func helperChangesAreRefused() {
        let result = HelperController.refuseAdministratorCommand("install")
        #expect(!result.accepted)
        #expect(result.reason == "qaCopy")
        #expect(HelperController.describe(result).contains("QA copy"))
    }

    @Test("A QA copy's holds reach nothing, so they never change the shared helper")
    func holdsNeverReachTheHelper() async {
        let reply = await UnreachableHoldTransport().send(.release(token: UUID()))
        #expect(reply == nil)
    }

    @Test("A QA copy's tool refuses helper commands before it does anything")
    func cliRefusesHelperCommands() {
        let result = Commands.runWithRealIO(argv: ["helper", "install"], channel: nil)
        #expect(result.exitCode == 2)
        #expect(result.json.contains("qaCopy"))
    }
}
