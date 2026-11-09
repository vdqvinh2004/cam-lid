import Foundation
import Testing
@testable import CamLidApp

/// Spec 022 (FR-006 to FR-008, SC-002): the button writes exactly one file under the home folder, and turning it off
/// removes only that file. Every test uses its own home folder, never the real one.
@Suite("Agent skill file") @MainActor
struct AgentSkillInstallerTests {
    private static let skill = Data("---\nname: camlid\n---\n# CamLid\n".utf8)
    private static let foreign = Data("someone else's skill\n".utf8)

    /// A fresh home folder and an in-memory preference store, so no preferences file is written.
    private func withHome(_ body: (URL, MemoryPreferences) throws -> Void) rethrows {
        let defaults = MemoryPreferences()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("camlid-home-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home, defaults)
    }

    private func installer(_ home: URL, _ defaults: any PreferenceStore) -> AgentSkillInstaller {
        AgentSkillInstaller(home: home, defaults: defaults, bundled: { Self.skill })
    }

    private func target(in home: URL) -> URL {
        home.appendingPathComponent(AgentSkillInstaller.relativePath)
    }

    /// Every regular file under the home folder, relative to it.
    private func files(under home: URL) -> [String] {
        let manager = FileManager.default
        return ((try? manager.subpathsOfDirectory(atPath: home.path)) ?? []).filter { subpath in
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: home.appendingPathComponent(subpath).path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }.sorted()
    }

    @Test func installWritesExactlyOneFileAndRemembersIt() throws {
        try withHome { home, defaults in
            let agent = installer(home, defaults)
            #expect(agent.perform(.install(replacing: false)) == .installed)
            #expect(files(under: home) == [AgentSkillInstaller.relativePath])
            let written = try Data(contentsOf: target(in: home))
            #expect(written == Self.skill)
            #expect(agent.installedPath == target(in: home).path)
        }
    }

    @Test func aSkillFileCamLidDidNotWriteIsReplacedOnlyWithConsent() throws {
        try withHome { home, defaults in
            try FileManager.default.createDirectory(at: target(in: home).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.foreign.write(to: target(in: home))
            let agent = installer(home, defaults)
            #expect(agent.perform(.install(replacing: false)) == .conflict(path: target(in: home).path))
            let kept = try Data(contentsOf: target(in: home))
            #expect(kept == Self.foreign)
            #expect(agent.installedPath == nil)
            #expect(agent.perform(.install(replacing: true)) == .installed)
            let replaced = try Data(contentsOf: target(in: home))
            #expect(replaced == Self.skill)
        }
    }

    @Test func removeDeletesOnlyTheFileItWrote() throws {
        try withHome { home, defaults in
            let agent = installer(home, defaults)
            _ = agent.perform(.install(replacing: false))
            let sibling = home.appendingPathComponent(".agents/skills/other/SKILL.md")
            try FileManager.default.createDirectory(at: sibling.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.foreign.write(to: sibling)
            try Data("notes\n".utf8).write(to: home.appendingPathComponent("notes.txt"))
            #expect(agent.perform(.remove) == .removed)
            #expect(files(under: home) == [".agents/skills/other/SKILL.md", "notes.txt"])
            #expect(agent.installedPath == nil)
        }
    }

    @Test func aFileChangedSinceInstallIsLeftInPlace() throws {
        try withHome { home, defaults in
            let agent = installer(home, defaults)
            _ = agent.perform(.install(replacing: false))
            try Data("edited by the user\n".utf8).write(to: target(in: home))
            #expect(agent.perform(.remove) == .keptModified)
            let edited = try Data(contentsOf: target(in: home))
            #expect(edited == Data("edited by the user\n".utf8))
            #expect(agent.installedPath == nil)
        }
    }

    @Test func aFileDeletedByHandIsReportedAndNotRecreated() throws {
        try withHome { home, defaults in
            let agent = installer(home, defaults)
            _ = agent.perform(.install(replacing: false))
            try FileManager.default.removeItem(at: target(in: home))
            #expect(agent.perform(.remove) == .nothingToRemove)
            #expect(files(under: home).isEmpty)
            #expect(agent.installedPath == nil)
        }
    }

    @Test func aFileCamLidNeverWroteIsNotRemovedEvenWhenIdentical() throws {
        try withHome { home, defaults in
            try FileManager.default.createDirectory(at: target(in: home).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.skill.write(to: target(in: home))
            #expect(installer(home, defaults).perform(.remove) == .nothingToRemove)
            #expect(FileManager.default.fileExists(atPath: target(in: home).path))
        }
    }

    @Test func theRecordSurvivesARelaunchAndAnUnchangedOwnFileIsUpdatedWithoutAsking() throws {
        try withHome { home, defaults in
            _ = installer(home, defaults).perform(.install(replacing: false))
            let relaunched = installer(home, defaults)
            #expect(relaunched.installedPath == target(in: home).path)
            #expect(relaunched.perform(.install(replacing: false)) == .installed)
            #expect(relaunched.perform(.remove) == .removed)
            #expect(files(under: home).isEmpty)
        }
    }

    @Test func aBuildWithoutTheBundledSkillWritesNothing() {
        withHome { home, defaults in
            let agent = AgentSkillInstaller(home: home, defaults: defaults, bundled: { nil })
            #expect(agent.perform(.install(replacing: false)) == .failed("This build has no bundled skill file."))
            #expect(files(under: home).isEmpty)
        }
    }

    /// Spec 023 hardening (security): a link on the path is never written through or removed.
    @Test func aLinkOnThePathIsNeverWrittenThrough() throws {
        try withHome { home, defaults in
            let elsewhere = home.appendingPathComponent("elsewhere.txt")
            try Self.foreign.write(to: elsewhere)
            try FileManager.default.createDirectory(at: target(in: home).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target(in: home), withDestinationURL: elsewhere)
            let agent = installer(home, defaults)
            guard case .failed = agent.perform(.install(replacing: true)) else {
                Issue.record("a link was written through")
                return
            }
            let untouched = try Data(contentsOf: elsewhere)
            #expect(untouched == Self.foreign)
            #expect(agent.installedPath == nil)
        }
    }

    @Test func aLinkedSkillsFolderIsRefused() throws {
        try withHome { home, defaults in
            let other = home.appendingPathComponent("other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".agents"), withDestinationURL: other)
            let agent = installer(home, defaults)
            guard case .failed = agent.perform(.install(replacing: false)) else {
                Issue.record("a linked skills folder was used")
                return
            }
            #expect(files(under: other).isEmpty)
        }
    }

    @Test func aFileReplacedByALinkIsNeverRemoved() throws {
        try withHome { home, defaults in
            let agent = installer(home, defaults)
            _ = agent.perform(.install(replacing: false))
            let elsewhere = home.appendingPathComponent("elsewhere.txt")
            try Self.skill.write(to: elsewhere)
            try FileManager.default.removeItem(at: target(in: home))
            try FileManager.default.createSymbolicLink(at: target(in: home), withDestinationURL: elsewhere)
            #expect(agent.perform(.remove) == .keptModified)
            #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        }
    }
}
