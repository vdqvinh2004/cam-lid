import Testing
import Foundation
@testable import CamLidCore

struct InstallerOwnershipTests {
    @Test func productionPreviewAndRemovalCannotTouchEvenOwnedConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-no-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("authored-owned-fixture.json")
        let content = #"{"camlidOwned":"camlid:owned:codex:v1"}"#
        try Data(content.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let descriptor = ProviderDescriptor(id: "codex", displayName: "Fixture", installs: [FileInstall(path: file.path, content: content)])
        let installer = IntegrationInstaller(filesystem: LocalConfigFileSystem())
        #expect(throws: ConfigFileError.integrationUnavailable(provider: "codex")) { try installer.preview(descriptors: [descriptor]) }
        #expect(throws: ConfigFileError.integrationUnavailable(provider: "codex")) { try installer.remove(descriptors: [descriptor]) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func productionInstallRefusesUnimplementedProviderProtocolBeforeIO() throws {
        // Refusal occurs before reading descriptor paths, so no host config is touched.
        #expect(throws: ConfigFileError.integrationUnavailable(provider: "claude")) {
            try IntegrationInstaller(filesystem: LocalConfigFileSystem()).install(descriptors: [.claude])
        }
    }
    @Test func unownedOrChangedSidecarCannotBeOverwritten() throws {
        let descriptor = ProviderDescriptor.codex; let path = descriptor.installs[0].path
        let current = #"{"user":"keep","camlidOwned":"camlid:owned:codex:v1"}"#
        let files = InMemoryConfigFileSystem(files: [path: current])
        #expect(throws: ConfigFileError.invalidData(path: path)) {
            try IntegrationInstaller(filesystem: files).install(descriptors: [descriptor])
        }
        #expect(try files.readFile(at: path) == current)
        #expect(try files.readFile(at: IntegrationInstaller.backupPath(for: path)) == nil)
    }
    @Test func laterNestedHookAndCustomNamespaceSurviveRemoval() throws {
        let descriptor = ProviderDescriptor.codex
        let install = descriptor.installs[0]
        let files = InMemoryConfigFileSystem()
        let installer = IntegrationInstaller(filesystem: files)
        _ = try installer.install(descriptors: [descriptor])
        var current = try JSONSerialization.jsonObject(with: Data((try files.readFile(at: install.path))!.utf8)) as! [String: Any]
        var hooks = current["hooks"] as! [String: Any]
        hooks["UserAdded"] = ["user-command"]
        current["hooks"] = hooks; current["camlidCustom"] = "user-owned"
        try files.writeFile(at: install.path, content: String(decoding: JSONSerialization.data(withJSONObject: current), as: UTF8.self))
        _ = try installer.remove(descriptors: [descriptor])
        let remaining = try JSONSerialization.jsonObject(with: Data((try files.readFile(at: install.path))!.utf8)) as! [String: Any]
        #expect((remaining["hooks"] as? [String: Any])?["UserAdded"] as? [String] == ["user-command"])
        #expect((remaining["hooks"] as? [String: Any])?["Stop"] == nil)
        #expect(remaining["camlidCustom"] as? String == "user-owned")
    }
    @Test func changedOwnedArrayIsPreservedWithBackup() throws {
        let descriptor = ProviderDescriptor.claude; let path = descriptor.installs[0].path
        let files = InMemoryConfigFileSystem(files: [path: #"{"user":true}"#])
        let installer = IntegrationInstaller(filesystem: files)
        _ = try installer.install(descriptors: [descriptor])
        var current = try JSONSerialization.jsonObject(with: Data((try files.readFile(at: path))!.utf8)) as! [String: Any]
        current["camlid"] = ["hooks": ["Stop": ["camlid-hook", "stop", "user-change"]]]
        try files.writeFile(at: path, content: String(decoding: JSONSerialization.data(withJSONObject: current), as: UTF8.self))
        #expect(throws: ConfigFileError.invalidData(path: path)) { try installer.install(descriptors: [descriptor]) }
        #expect(try files.readFile(at: path)?.contains("user-change") == true)
        _ = try installer.remove(descriptors: [descriptor])
        let remaining = try #require(try files.readFile(at: path))
        #expect(remaining.contains("user-change"))
        #expect(try files.readFile(at: IntegrationInstaller.backupPath(for: path)) != nil)
    }
    @Test func markerSubstringOrNamespaceDoesNotProveOwnership() throws {
        let descriptor = ProviderDescriptor.codex; let path = descriptor.installs[0].path
        let current = #"{"camlidCustom":"user-owned","note":"camlid:owned:codex:v1","hooks":{"UserAdded":["keep"]}}"#
        let files = InMemoryConfigFileSystem(files: [path: current])
        _ = try IntegrationInstaller(filesystem: files).remove(descriptors: [descriptor])
        #expect(try files.readFile(at: path) == current)
    }
    @Test func nestedMergePreservesUnrelatedKeysAndRefusesUnownedCollision() throws {
        let descriptor = ProviderDescriptor.claude; let path = descriptor.installs[0].path
        let files = InMemoryConfigFileSystem(files: [path: #"{"camlid":{"custom":"keep"},"hooks":{"UserAdded":["keep"]}}"#])
        _ = try IntegrationInstaller(filesystem: files).install(descriptors: [descriptor])
        #expect(try files.readFile(at: path)?.contains("custom") == true)
        let conflicting = InMemoryConfigFileSystem(files: [path: #"{"camlid":{"hooks":{"Stop":["user-owned"]}}}"#])
        #expect(throws: (any Error).self) { try IntegrationInstaller(filesystem: conflicting).install(descriptors: [descriptor]) }
        #expect(try conflicting.readFile(at: path) == #"{"camlid":{"hooks":{"Stop":["user-owned"]}}}"#)
    }
}
