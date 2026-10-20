import Foundation
import Testing
@testable import CamLidApp

struct AgentCLIInstallationTests {
    @Test func detectsExecutableWithoutRunningItAndIgnoresPlainFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["codex", "claude", "orca-cli"] {
            let url = root.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 99\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: name == "claude" ? 0o600 : 0o700], ofItemAtPath: url.path)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("opencode"), withIntermediateDirectories: false)
        #expect(AgentCLIInstallation.detected(directories: [root.path], orcaExecutable: "/missing/orca") == ["codex", "orca"])
        let state = AgentBadgeState(provider: "codex", enabled: false, tasks: [], cliDetected: true)
        #expect(state.installationText == "CLI detected" && state.observedState == "Not detected")
        #expect(try JSONDecoder().decode(AgentBadgeState.self, from: JSONEncoder().encode(state)).cliDetected == true)
    }
}
