import Foundation
import Testing
@testable import CamLidApp

/// Spec 022 (FR-006 to FR-008, SC-002): the button writes exactly one file, and turning it off removes only that file.
@Suite("Agent skill file") @MainActor
struct AgentSkillInstallerTests {
    private static let skill = Data("---\nname: camlid\n---\n# CamLid\n".utf8)
    private static let foreign = Data("someone else's skill\n".utf8)

    /// A fresh project folder and an isolated preferences suite, removed afterwards.
    private func withProject(_ body: (URL, UserDefaults) throws -> Void) rethrows {
        let suite = "camlid.tests.skill." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("camlid-skill-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        try body(folder, defaults)
    }

    private func installer(_ defaults: UserDefaults) -> AgentSkillInstaller {
        AgentSkillInstaller(defaults: defaults, bundled: { Self.skill })
    }

    private func target(in folder: URL) -> URL {
        folder.appendingPathComponent(AgentSkillInstaller.relativePath)
    }

    /// Every regular file under the folder, relative to it.
    private func files(under folder: URL) -> [String] {
        let manager = FileManager.default
        return ((try? manager.subpathsOfDirectory(atPath: folder.path)) ?? []).filter { subpath in
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: folder.appendingPathComponent(subpath).path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }.sorted()
    }

    @Test func installWritesExactlyOneFileAndRemembersIt() throws {
        try withProject { folder, defaults in
            let agent = installer(defaults)
            #expect(agent.perform(.install(folder: folder.path, replacing: false)) == .installed)
            #expect(files(under: folder) == [AgentSkillInstaller.relativePath])
            let written = try Data(contentsOf: target(in: folder))
            #expect(written == Self.skill)
            #expect(agent.installedFolder == folder.path)
        }
    }

    @Test func aSkillFileCamLidDidNotWriteIsReplacedOnlyWithConsent() throws {
        try withProject { folder, defaults in
            try FileManager.default.createDirectory(at: target(in: folder).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.foreign.write(to: target(in: folder))
            let agent = installer(defaults)
            #expect(agent.perform(.install(folder: folder.path, replacing: false)) == .conflict(folder: folder.path))
            let kept = try Data(contentsOf: target(in: folder))
            #expect(kept == Self.foreign)
            #expect(agent.installedFolder == nil)
            #expect(agent.perform(.install(folder: folder.path, replacing: true)) == .installed)
            let replaced = try Data(contentsOf: target(in: folder))
            #expect(replaced == Self.skill)
        }
    }

    @Test func removeDeletesOnlyTheFileItWrote() throws {
        try withProject { folder, defaults in
            let agent = installer(defaults)
            _ = agent.perform(.install(folder: folder.path, replacing: false))
            let sibling = folder.appendingPathComponent(".agents/skills/other/SKILL.md")
            try FileManager.default.createDirectory(at: sibling.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.foreign.write(to: sibling)
            try Data("notes\n".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            #expect(agent.perform(.remove) == .removed)
            #expect(files(under: folder) == [".agents/skills/other/SKILL.md", "notes.txt"])
            #expect(agent.installedFolder == nil)
        }
    }

    @Test func aFileChangedSinceInstallIsLeftInPlace() throws {
        try withProject { folder, defaults in
            let agent = installer(defaults)
            _ = agent.perform(.install(folder: folder.path, replacing: false))
            try Data("edited by the user\n".utf8).write(to: target(in: folder))
            #expect(agent.perform(.remove) == .keptModified)
            let edited = try Data(contentsOf: target(in: folder))
            #expect(edited == Data("edited by the user\n".utf8))
            #expect(agent.installedFolder == nil)
        }
    }

    @Test func aFileDeletedByHandIsReportedAndNotRecreated() throws {
        try withProject { folder, defaults in
            let agent = installer(defaults)
            _ = agent.perform(.install(folder: folder.path, replacing: false))
            try FileManager.default.removeItem(at: target(in: folder))
            #expect(agent.perform(.remove) == .nothingToRemove)
            #expect(files(under: folder).isEmpty)
            #expect(agent.installedFolder == nil)
        }
    }

    @Test func aFileCamLidNeverWroteIsNotRemovedEvenWhenIdentical() throws {
        try withProject { folder, defaults in
            try FileManager.default.createDirectory(at: target(in: folder).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.skill.write(to: target(in: folder))
            #expect(installer(defaults).perform(.remove) == .nothingToRemove)
            #expect(FileManager.default.fileExists(atPath: target(in: folder).path))
        }
    }

    @Test func theRecordSurvivesARelaunchAndOnlyOneFolderIsAllowed() throws {
        try withProject { folder, defaults in
            let other = folder.appendingPathComponent("other-project", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            _ = installer(defaults).perform(.install(folder: folder.path, replacing: false))
            let relaunched = installer(defaults)
            #expect(relaunched.installedFolder == folder.path)
            guard case .failed = relaunched.perform(.install(folder: other.path, replacing: false)) else {
                Issue.record("a second folder was accepted while the first still holds the file")
                return
            }
            #expect(relaunched.perform(.remove) == .removed)
        }
    }

    @Test func aBuildWithoutTheBundledSkillWritesNothing() {
        withProject { folder, defaults in
            let agent = AgentSkillInstaller(defaults: defaults, bundled: { nil })
            #expect(agent.perform(.install(folder: folder.path, replacing: false)) == .failed("This build has no bundled skill file."))
            #expect(files(under: folder).isEmpty)
        }
    }

    /// Spec 023 hardening (security): a link on the path is never written through or removed.
    @Test func aLinkOnThePathIsNeverWrittenThrough() throws {
        try withProject { folder, defaults in
            let elsewhere = folder.appendingPathComponent("elsewhere.txt")
            try Self.foreign.write(to: elsewhere)
            try FileManager.default.createDirectory(at: target(in: folder).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target(in: folder), withDestinationURL: elsewhere)
            let agent = installer(defaults)
            guard case .failed = agent.perform(.install(folder: folder.path, replacing: true)) else {
                Issue.record("a link was written through")
                return
            }
            let untouched = try Data(contentsOf: elsewhere)
            #expect(untouched == Self.foreign)
            #expect(agent.installedFolder == nil)
        }
    }

    @Test func aLinkedFolderIsRefused() throws {
        try withProject { folder, defaults in
            let other = folder.appendingPathComponent("other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(".agents"), withDestinationURL: other)
            let agent = installer(defaults)
            guard case .failed = agent.perform(.install(folder: folder.path, replacing: false)) else {
                Issue.record("a linked folder was used")
                return
            }
            #expect(files(under: other).isEmpty)
        }
    }

    @Test func aFileReplacedByALinkIsNeverRemoved() throws {
        try withProject { folder, defaults in
            let agent = installer(defaults)
            _ = agent.perform(.install(folder: folder.path, replacing: false))
            let elsewhere = folder.appendingPathComponent("elsewhere.txt")
            try Self.skill.write(to: elsewhere)
            try FileManager.default.removeItem(at: target(in: folder))
            try FileManager.default.createSymbolicLink(at: target(in: folder), withDestinationURL: elsewhere)
            #expect(agent.perform(.remove) == .keptModified)
            #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        }
    }
}
