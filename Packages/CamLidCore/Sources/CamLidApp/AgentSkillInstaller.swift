import CryptoKit
import Foundation

/// A request from the Settings window. The window picks the folder; the app writes the file.
enum AgentSkillRequest: Codable, Sendable, Equatable {
    case install(folder: String, replacing: Bool)
    case remove
}

/// The result, so the window can ask before replacing a file CamLid did not write.
enum AgentSkillOutcome: Codable, Sendable, Equatable {
    case installed, removed, nothingToRemove, keptModified
    case conflict(folder: String)
    case failed(String)
}

/// Writes one agent skill file into a project folder the user chose (spec 022). CamLid owns a file only if it wrote
/// it: it asks before replacing any other SKILL.md, and it removes only its own file, and only while its contents are
/// unchanged. Nothing is written at launch.
struct AgentSkillInstaller {
    static let relativePath = ".agents/skills/camlid/SKILL.md"
    static let recordKey = "CamLidAgentSkillInstall"

    private struct Record: Codable { let folder: String; let sha256: String }

    let defaults: UserDefaults
    /// The SKILL.md copied into the app at build time; nil only if that copy is missing.
    let bundled: () -> Data?

    /// The folder CamLid installed the skill in, or nil.
    var installedFolder: String? { record?.folder }

    func perform(_ request: AgentSkillRequest) -> AgentSkillOutcome {
        switch request {
        case .install(let folder, let replacing):
            return install(into: URL(fileURLWithPath: folder, isDirectory: true), replacing: replacing)
        case .remove:
            return remove()
        }
    }

    private func install(into folder: URL, replacing: Bool) -> AgentSkillOutcome {
        // One installation at a time: a second folder would leave the first file with no way to remove it.
        if let installed = record {
            return installed.folder == folder.path ? .installed
                : .failed("CamLid already installed the skill in \(installed.folder). Turn it off there first.")
        }
        guard let content = bundled() else { return .failed("This build has no bundled skill file.") }
        // A link on the path would send the write somewhere the user did not choose. CamLid writes plain files only.
        guard !Self.containsSymbolicLink(in: folder) else {
            return .failed("The skill path contains a symbolic link, so CamLid did not write through it.")
        }
        let target = folder.appendingPathComponent(Self.relativePath)
        if !replacing, FileManager.default.fileExists(atPath: target.path) { return .conflict(folder: folder.path) }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: target, options: .atomic)
        } catch {
            return .failed(error.localizedDescription)
        }
        record = Record(folder: folder.path, sha256: Self.digest(content))
        return .installed
    }

    private func remove() -> AgentSkillOutcome {
        guard let installed = record else { return .nothingToRemove }
        let target = URL(fileURLWithPath: installed.folder, isDirectory: true).appendingPathComponent(Self.relativePath)
        guard FileManager.default.fileExists(atPath: target.path) else {
            record = nil
            return .nothingToRemove
        }
        // Never remove through a link: CamLid never writes one, so a link here is not the file it wrote.
        guard !Self.containsSymbolicLink(in: URL(fileURLWithPath: installed.folder, isDirectory: true)) else {
            record = nil
            return .keptModified
        }
        guard let data = try? Data(contentsOf: target) else {
            return .failed("CamLid could not read the skill file, so it left the file in place.")
        }
        guard Self.digest(data) == installed.sha256 else {
            record = nil
            return .keptModified
        }
        do {
            try FileManager.default.removeItem(at: target)
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

    /// True when a component between the project folder and the skill file is a symbolic link, the file itself included.
    static func containsSymbolicLink(in folder: URL) -> Bool {
        var current = folder
        for component in relativePath.split(separator: "/") {
            current = current.appendingPathComponent(String(component))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        }
        return false
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
