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

    /// A GUI app is launchd-launched with a PATH that has no shell-managed bin: freebuff must be found where its own
    /// installer put the native build, with nothing on PATH.
    @Test func freebuffIsFoundWhereItsInstallerPutsItWithoutAShellPath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let install = home.appendingPathComponent(".config/manicode")
        try FileManager.default.createDirectory(at: install, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let url = install.appendingPathComponent("freebuff")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let directories = AgentCLIInstallation.searchDirectories(home: home.path, environmentPath: "/usr/bin:/bin:/usr/sbin:/sbin")
        let snapshot = AgentCLIInstallation.snapshot(directories: directories, orcaExecutable: "/missing/orca",
            applicationDetector: { _ in false })
        #expect(snapshot.cliDetected.contains("freebuff"))
    }
}
