import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Authoritative preference file trust", .serialized)
struct PreferenceFileTrustTests {
    @Test @MainActor func danglingLinkCannotResurrectLegacySettings() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let history = fixture.root.appendingPathComponent("history")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: history.appendingPathComponent("preferences.json").path,
            withDestinationPath: fixture.root.appendingPathComponent("missing.json").path)
        let defaults = fixture.preferences
        defaults.set(try JSONEncoder().encode(Configuration(completionDelayMinutes: 7)), forKey: "CamLidConfigurationV1")
        defaults.set(Data(#"{"schemaVersion":1,"revision":9,"configuration":{"mode":"off","completionDelayMinutes":7}}"#.utf8), forKey: "CamLidConfigurationV2")
        let app = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.configGet, payload: Data()))
        #expect(reply.json.contains("\"completionDelayMinutes\":2") && reply.json.contains("\"revision\":1"))
    }

    @Test @MainActor func sharedOrOversizedAuthoritativeFileIsRejected() throws {
        for oversized in [false, true] {
            let fixture = QARefinementSupport(); defer { fixture.cleanup() }
            let app = fixture.makeCoordinator()
            var patch = ConfigPatch(); patch.completionDelayMinutes = 7
            guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("Expected setup write"); return }
            let file = fixture.root.appendingPathComponent("history/preferences.json")
            if oversized { try Data(repeating: 32, count: 65_537).write(to: file) }
            try FileManager.default.setAttributes([.posixPermissions: oversized ? 0o600 : 0o644], ofItemAtPath: file.path)
            let restored = fixture.makeCoordinator()
            let reply = try JSONDecoder().decode(CLIResult.self, from: restored.handleControl(.configGet, payload: Data()))
            #expect(reply.json.contains("\"completionDelayMinutes\":2") && reply.json.contains("\"revision\":1"))
        }
    }
}
