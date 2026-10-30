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
        #expect(AgentCLIInstallation.detected(directories: [root.path],
            orcaExecutable: "/missing/orca", applicationDetector: { _ in false }) == ["codex", "orca"])
        let state = AgentBadgeState(provider: "codex", enabled: false, tasks: [], cliDetected: true)
        #expect(state.installationText == "CLI detected" && state.observedState == "Not detected")
        #expect(try JSONDecoder().decode(AgentBadgeState.self, from: JSONEncoder().encode(state)).cliDetected == true)
    }

    @Test func detectsNewCLIsAndApplicationBundlesSeparately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["freebuff", "pi"] {
            let url = root.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 99\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        let snapshot = AgentCLIInstallation.snapshot(directories: [root.path],
            orcaExecutable: "/missing/orca",
            applicationDetector: { $0 == "com.openai.codex" })
        #expect(snapshot.cliDetected == ["freebuff", "pi"])
        #expect(snapshot.appDetected == ["codex"])
        #expect(snapshot.allDetected == ["codex", "freebuff", "pi"])
    }
}
