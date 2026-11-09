import CryptoKit
import Foundation

/// A request from the Settings window. The window only asks; the app writes the file.
enum AgentSkillRequest: Codable, Sendable, Equatable {
    case install(replacing: Bool)
    case remove
}

/// The result, so the window can ask before replacing a file CamLid did not write.
enum AgentSkillOutcome: Codable, Sendable, Equatable {
    case installed, removed, nothingToRemove, keptModified
    case conflict(path: String)
    case failed(String)
}

/// Writes one agent skill file, `~/.agents/skills/camlid/SKILL.md` under the home folder (spec 022). CamLid owns a file
/// only if it wrote it: it asks before replacing any other SKILL.md, and it removes only its own file, and only while its
/// contents are unchanged. Nothing is written at launch.
struct AgentSkillInstaller {
    static let relativePath = ".agents/skills/camlid/SKILL.md"
    static let recordKey = "CamLidAgentSkillInstall"

    private struct Record: Codable { let sha256: String }

    /// The folder the file goes under: the user's home folder, or a QA run's own folder.
    let home: URL
    let defaults: any PreferenceStore
    /// The SKILL.md copied into the app at build time; nil only if that copy is missing.
    let bundled: () -> Data?

    /// Where the file is.
    var location: URL { home.appendingPathComponent(Self.relativePath) }

    /// The path CamLid installed the file at, or nil.
    var installedPath: String? { record == nil ? nil : location.path }

    func perform(_ request: AgentSkillRequest) -> AgentSkillOutcome {
        switch request {
        case .install(let replacing):
            return install(replacing: replacing)
        case .remove:
            return remove()
        }
    }

    private func install(replacing: Bool) -> AgentSkillOutcome {
        guard let content = bundled() else { return .failed("This build has no bundled skill file.") }
        // A link on the path would send the write somewhere else. CamLid writes plain files only.
        guard !Self.containsSymbolicLink(in: home) else {
            return .failed("The skill path contains a symbolic link, so CamLid did not write through it.")
        }
        let exists = FileManager.default.fileExists(atPath: location.path)
        // CamLid's own file, unchanged since it wrote it, is updated without asking. Anything else needs consent.
        let isOwnUnchanged = exists && record != nil && Self.digestOfFile(location) == record?.sha256
        if exists, !isOwnUnchanged, !replacing { return .conflict(path: location.path) }
        do {
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: location, options: .atomic)
        } catch {
            return .failed(error.localizedDescription)
        }
        record = Record(sha256: Self.digest(content))
        return .installed
    }

    private func remove() -> AgentSkillOutcome {
        guard let installed = record else { return .nothingToRemove }
        guard FileManager.default.fileExists(atPath: location.path) else {
            record = nil
            return .nothingToRemove
        }
        // Never remove through a link: CamLid never writes one, so a link here is not the file it wrote.
        guard !Self.containsSymbolicLink(in: home) else {
            record = nil
            return .keptModified
        }
        guard let data = try? Data(contentsOf: location) else {
            return .failed("CamLid could not read the skill file, so it left the file in place.")
        }
        guard Self.digest(data) == installed.sha256 else {
            record = nil
            return .keptModified
        }
        do {
            try FileManager.default.removeItem(at: location)
            record = nil
            return .removed
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private var record: Record? {
        get { defaults.data(forKey: Self.recordKey).flatMap { try? JSONDecoder().decode(Record.self, from: $0) } }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.recordKey) }
    }

    /// True when a component between the home folder and the skill file is a symbolic link, the file itself included.
    static func containsSymbolicLink(in home: URL) -> Bool {
        var current = home
        for component in relativePath.split(separator: "/") {
            current = current.appendingPathComponent(String(component))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        }
        return false
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func digestOfFile(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map(digest)
    }
}
