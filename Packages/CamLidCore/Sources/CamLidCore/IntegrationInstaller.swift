/// Integration preview/install/removal for agent providers (M3 T007).
///
/// `IntegrationInstaller` operates only on an injected `ConfigFileSystem`.
/// Only `InMemoryConfigFileSystem` is admitted: legacy storage regression fixtures.
/// Preview/install/removal refuse every other filesystem before IO.
///
/// Rules:
/// - Preview reports planned writes as a line diff before anything changes.
/// - Install backs up existing content (first backup wins) then writes.
///   Shared JSON settings merge CamLid-owned namespaced keys while preserving
///   all unknown existing keys; sidecar files are written with an owned
///   marker. Files already containing an Orca management marker
///   (`orca:managed`) are never overwritten: Orca-managed hooks are preserved.
/// - Removal restores backups where present, otherwise removes only
///   CamLid-owned content (owned marker or owned JSON keys). Unowned content
///   is never touched.
import Foundation

public enum ConfigFileError: Error, Sendable, Equatable {
    case notFound(path: String)
    case unreadable(path: String)
    case unwritable(path: String)
    case invalidData(path: String)
    case integrationUnavailable(provider: String)
}

/// File-system seam for integration install/preview/removal.
public protocol ConfigFileSystem: Sendable {
    func readFile(at path: String) throws(ConfigFileError) -> String?
    func writeFile(at path: String, content: String) throws(ConfigFileError)
    func removeFile(at path: String) throws(ConfigFileError)
    func listDirectory(at path: String) throws(ConfigFileError) -> [String]
}

/// In-memory file system for tests. Never touches disk.
public final class InMemoryConfigFileSystem: ConfigFileSystem, @unchecked Sendable {
    private var files: [String: String]
    private let lock = NSLock()

    public init(files: [String: String] = [:]) {
        self.files = files
    }

    public func readFile(at path: String) throws(ConfigFileError) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return files[path]
    }

    public func writeFile(at path: String, content: String) throws(ConfigFileError) {
        lock.lock()
        defer { lock.unlock() }
        files[path] = content
    }

    public func removeFile(at path: String) throws(ConfigFileError) {
        lock.lock()
        defer { lock.unlock() }
        guard files[path] != nil else {
            throw ConfigFileError.notFound(path: path)
        }
        files.removeValue(forKey: path)
    }

    public func listDirectory(at path: String) throws(ConfigFileError) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return files.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}

/// Tilde-expanding FileManager-backed file system for production callers.
/// Never used in tests.
public struct LocalConfigFileSystem: ConfigFileSystem {
    public init() {}

    private func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    public func readFile(at path: String) throws(ConfigFileError) -> String? {
        let full = expanded(path)
        guard FileManager.default.fileExists(atPath: full) else { return nil }
        guard let content = try? String(contentsOfFile: full, encoding: .utf8) else {
            throw ConfigFileError.unreadable(path: path)
        }
        return content
    }

    public func writeFile(at path: String, content: String) throws(ConfigFileError) {
        let full = expanded(path)
        let directory = (full as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true)
            try content.write(toFile: full, atomically: true, encoding: .utf8)
        } catch {
            throw ConfigFileError.unwritable(path: path)
        }
    }

    public func removeFile(at path: String) throws(ConfigFileError) {
        let full = expanded(path)
        guard FileManager.default.fileExists(atPath: full) else {
            throw ConfigFileError.notFound(path: path)
        }
        do {
            try FileManager.default.removeItem(atPath: full)
        } catch {
            throw ConfigFileError.unwritable(path: path)
        }
    }

    public func listDirectory(at path: String) throws(ConfigFileError) -> [String] {
        let full = expanded(path)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: full) else {
            throw ConfigFileError.notFound(path: path)
        }
        return entries.sorted()
    }
}

/// Owned-marker format shared by every file CamLid writes:
/// a line or JSON value containing `camlid:owned:<provider>:v1`.
public enum OwnedMarker {
    public static let prefix = "camlid:owned:"
    public static let version = "v1"
    public static func text(for provider: String) -> String {
        "\(prefix)\(provider):\(version)"
    }
    public static func isOwned(_ content: String, provider: String) -> Bool {
        content.contains(text(for: provider))
    }
    /// Content the installer refuses to overwrite: Orca-managed hooks.
    public static func isOrcaManaged(_ content: String) -> Bool {
        content.contains("orca:managed")
    }
}

public struct FileInstall: Sendable, Equatable {
    /// Install path; `~` expands only in `LocalConfigFileSystem`.
    public let path: String
    public let content: String
    /// When true and existing content parses as a JSON object, CamLid-owned
    /// namespaced keys merge in while every unknown existing key is preserved.
    public let mergesJSON: Bool
    public init(path: String, content: String, mergesJSON: Bool = false) {
        self.path = path
        self.content = content
        self.mergesJSON = mergesJSON
    }
}

/// Provider install descriptor: install paths plus owned-marker format.
public struct ProviderDescriptor: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let installs: [FileInstall]
    /// True when another manager owns this provider's hooks: the installer
    /// writes nothing for it (coexistence only).
    public let managedExternally: Bool
    public let notes: String

    public init(
        id: String, displayName: String, installs: [FileInstall] = [],
        managedExternally: Bool = false, notes: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.installs = installs
        self.managedExternally = managedExternally
        self.notes = notes
    }

    /// Claude Code: merges CamLid-owned namespaced keys into the user
    /// settings file, preserving all existing keys (including the user's own
    /// `hooks` entry, which is never modified).
    public static var claude: ProviderDescriptor {
        let marker = OwnedMarker.text(for: "claude")
        let content = """
            {
              "camlid": {
                "hooks": {
                  "UserPromptSubmit": ["camlid-hook", "prompt-submit"],
                  "Stop": ["camlid-hook", "stop"]
                }
              },
              "camlidOwned": "\(marker)"
            }
            """
        return ProviderDescriptor(
            id: "claude", displayName: "Claude Code",
            installs: [FileInstall(
                path: "~/.claude/settings.json", content: content, mergesJSON: true)],
            notes: "Merges namespaced camlid keys; user hooks preserved.")
    }

    /// Codex CLI: CamLid-owned sidecar hook file. The user points their
    /// opt-in Codex hooks configuration at this file.
    public static var codex: ProviderDescriptor {
        let marker = OwnedMarker.text(for: "codex")
        let content = """
            {
              "hooks": {
                "UserPromptSubmit": ["camlid-hook", "prompt-submit"],
                "Stop": ["camlid-hook", "stop"]
              },
              "camlidOwned": "\(marker)"
            }
            """
        return ProviderDescriptor(
            id: "codex", displayName: "Codex CLI",
            installs: [FileInstall(path: "~/.codex/camlid-hooks.json", content: content)],
            notes: "Sidecar file; user opts in by referencing it from Codex hooks.")
    }

    /// OpenCode: CamLid-owned sidecar for the configured loopback/plugin
    /// integration. No port scanning; the endpoint is configured explicitly.
    public static var opencode: ProviderDescriptor {
        let marker = OwnedMarker.text(for: "opencode")
        let content = """
            {
              "camlidPlugin": {
                "loopbackEndpoint": "127.0.0.1:4096"
              },
              "camlidOwned": "\(marker)"
            }
            """
        return ProviderDescriptor(
            id: "opencode", displayName: "OpenCode",
            installs: [FileInstall(path: "~/.config/opencode/camlid.json", content: content)],
            notes: "Sidecar file; user configures the loopback endpoint explicitly.")
    }

    /// Orca: externally managed. The installer writes nothing and never
    /// overwrites Orca-managed hooks; coexistence is via the versioned JSON
    /// CLI snapshot adapter only.
    public static var orca: ProviderDescriptor {
        ProviderDescriptor(
            id: "orca", displayName: "Orca", installs: [],
            managedExternally: true,
            notes: "Orca-managed; installer writes no hooks. Never overwrite Orca-managed content.")
    }

    public static var all: [ProviderDescriptor] {
        [.claude, .codex, .opencode, .orca]
    }
}

public enum PlannedAction: String, Sendable, Equatable {
    case create
    case update
    case mergeJSON
    case unchanged
    case skipOrcaManaged
    case skipExternallyManaged
}

public struct PlannedWrite: Sendable, Equatable {
    public let path: String
    public let action: PlannedAction
    public let diff: String
    public let backupPath: String?
}

public struct AppliedWrite: Sendable, Equatable {
    public let path: String
    public let action: PlannedAction
    public let backupPath: String?
    public let diff: String
}

public enum RemovedAction: String, Sendable, Equatable {
    case restoredBackup
    case removedOwned
    case prunedOwnedKeys
    case leftUnowned
    /// User edited the file after install: owned entries were removed from
    /// current content while unrelated post-install edits were preserved.
    /// Ambiguous edits retain the full-file backup for deliberate recovery.
    case preservedEdits
}

public struct RemovedEntry: Sendable, Equatable {
    public let path: String
    public let action: RemovedAction
    public let backupPath: String?
}

public struct IntegrationInstaller: Sendable {
    public let filesystem: any ConfigFileSystem

    public init(filesystem: any ConfigFileSystem) {
        self.filesystem = filesystem
    }

    public static func backupPath(for path: String) -> String {
        path + ".camlid-backup"
    }

    private func requireFixtureFilesystem(_ descriptors: [ProviderDescriptor]) throws(ConfigFileError) {
        guard filesystem is InMemoryConfigFileSystem else {
            throw ConfigFileError.integrationUnavailable(provider: descriptors.first?.id ?? "unknown")
        }
    }

    /// Legacy storage fixtures only; production never reads provider configuration.
    public func preview(descriptors: [ProviderDescriptor]) throws(ConfigFileError) -> [PlannedWrite] {
        try requireFixtureFilesystem(descriptors)
        var plans: [PlannedWrite] = []
        for descriptor in descriptors {
            if descriptor.managedExternally {
                continue
            }
            for install in descriptor.installs {
                plans.append(try planWrite(descriptor: descriptor, install: install))
            }
        }
        return plans
    }

    /// Install: backup existing content (first backup wins), then write.
    /// Shared JSON settings merge owned keys while preserving unknown keys.
    /// Malformed shared JSON refuses with `invalidData` instead of replacing.
    public func install(descriptors: [ProviderDescriptor]) throws(ConfigFileError) -> [AppliedWrite] {
        try requireFixtureFilesystem(descriptors)
        var applied: [AppliedWrite] = []
        for descriptor in descriptors {
            if descriptor.managedExternally {
                continue
            }
            for install in descriptor.installs {
                let plan = try planWrite(descriptor: descriptor, install: install)
                switch plan.action {
                case .unchanged, .skipOrcaManaged, .skipExternallyManaged:
                    applied.append(AppliedWrite(
                        path: plan.path, action: plan.action,
                        backupPath: plan.backupPath, diff: plan.diff))
                case .create, .update, .mergeJSON:
                    let existing = try filesystem.readFile(at: install.path)
                    var backup: String? = nil
                    if let existing, !existing.isEmpty {
                        backup = Self.backupPath(for: install.path)
                        if try filesystem.readFile(at: backup!) == nil {
                            try filesystem.writeFile(at: backup!, content: existing)
                        }
                    }
                    try filesystem.writeFile(at: install.path, content: try mergedContent(
                        descriptor: descriptor, install: install, existing: existing))
                    applied.append(AppliedWrite(
                        path: plan.path, action: plan.action,
                        backupPath: backup, diff: plan.diff))
                }
            }
        }
        return applied
    }

    /// Removal (F08): remove ONLY proven owned entries from CURRENT content,
    /// preserving unrelated post-install edits. A full-file backup restores
    /// ONLY when current content is byte-identical to what install wrote
    /// (exact-state/ownership proof, no user edits); otherwise current minus
    /// owned entries is kept and reported as `preservedEdits`. Malformed
    /// shared JSON refuses with `invalidData`. Orca-managed content is never
    /// touched. Unowned content is left untouched.
    public func remove(descriptors: [ProviderDescriptor]) throws(ConfigFileError) -> [RemovedEntry] {
        try requireFixtureFilesystem(descriptors)
        var removed: [RemovedEntry] = []
        for descriptor in descriptors {
            if descriptor.managedExternally {
                continue
            }
            for install in descriptor.installs {
                let backup = Self.backupPath(for: install.path)
                let backupContent = try filesystem.readFile(at: backup)
                guard let current = try filesystem.readFile(at: install.path) else {
                    if let _ = backupContent {
                        // User deleted the file: keep deletion and its recovery backup.
                        removed.append(RemovedEntry(
                            path: install.path, action: .preservedEdits, backupPath: backup))
                    } else {
                        removed.append(RemovedEntry(
                            path: install.path, action: .leftUnowned, backupPath: nil))
                    }
                    continue
                }
                if OwnedMarker.isOrcaManaged(current) {
                    removed.append(RemovedEntry(
                        path: install.path, action: .leftUnowned, backupPath: nil))
                    continue
                }
                if let backupContent {
                    let expected = try expectedInstalledContent(
                        descriptor: descriptor, install: install,
                        backupContent: backupContent)
                    if current == expected {
                        try filesystem.writeFile(at: install.path, content: backupContent)
                        try filesystem.removeFile(at: backup)
                        removed.append(RemovedEntry(
                            path: install.path, action: .restoredBackup, backupPath: backup))
                        continue
                    }
                    // User edited after install: prune owned from current.
                    if install.mergesJSON, !Self.isJSONObject(current) {
                        throw ConfigFileError.invalidData(path: install.path)
                    }
                    if let pruned = Self.prunedOwnedJSON(
                        content: current, provider: descriptor.id, install: install, originalContent: backupContent)
                    {
                        if pruned.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
                            try filesystem.removeFile(at: install.path)
                        } else {
                            try filesystem.writeFile(at: install.path, content: pruned)
                        }
                        removed.append(RemovedEntry(
                            path: install.path, action: .preservedEdits, backupPath: backup))
                        continue
                    }
                    if !Self.isJSONObject(current), let prunedText = Self.prunedOwnedLines(
                        content: current, provider: descriptor.id),
                        prunedText != current
                    {
                        if prunedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try filesystem.removeFile(at: install.path)
                        } else {
                            try filesystem.writeFile(at: install.path, content: prunedText)
                        }
                        removed.append(RemovedEntry(
                            path: install.path, action: .preservedEdits, backupPath: backup))
                        continue
                    }
                    // Ownership is ambiguous: preserve both current and backup.
                    removed.append(RemovedEntry(
                        path: install.path, action: .preservedEdits, backupPath: backup))
                    continue
                }
                // No backup: remove only proven owned entries. A file
                // byte-identical to what install wrote is cleanly owned.
                if current == install.content {
                    try filesystem.removeFile(at: install.path)
                    removed.append(RemovedEntry(
                        path: install.path, action: .removedOwned, backupPath: nil))
                    continue
                }
                if install.mergesJSON, !Self.isJSONObject(current) {
                    throw ConfigFileError.invalidData(path: install.path)
                }
                if let pruned = Self.prunedOwnedJSON(
                    content: current, provider: descriptor.id, install: install)
                {
                    if pruned.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
                        try filesystem.removeFile(at: install.path)
                        removed.append(RemovedEntry(
                            path: install.path, action: .removedOwned, backupPath: nil))
                    } else {
                        try filesystem.writeFile(at: install.path, content: pruned)
                        removed.append(RemovedEntry(
                            path: install.path, action: .preservedEdits, backupPath: nil))
                    }
                    continue
                }
                if install.mergesJSON {
                    removed.append(RemovedEntry(
                        path: install.path, action: .leftUnowned, backupPath: nil))
                    continue
                }
                if OwnedMarker.isOwned(current, provider: descriptor.id) {
                    if !Self.isJSONObject(current), let prunedText = Self.prunedOwnedLines(
                        content: current, provider: descriptor.id),
                        prunedText != current
                    {
                        if prunedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try filesystem.removeFile(at: install.path)
                            removed.append(RemovedEntry(
                                path: install.path, action: .removedOwned, backupPath: nil))
                        } else {
                            try filesystem.writeFile(at: install.path, content: prunedText)
                            removed.append(RemovedEntry(
                                path: install.path, action: .preservedEdits, backupPath: nil))
                        }
                        continue
                    }
                    // A substring cannot prove whole-file ownership; the exact
                    // descriptor case above is the only whole-file deletion.
                    removed.append(RemovedEntry(
                        path: install.path, action: .leftUnowned, backupPath: nil))
                } else {
                    removed.append(RemovedEntry(
                        path: install.path, action: .leftUnowned, backupPath: nil))
                }
            }
        }
        return removed
    }

    // MARK: - Private

    private func planWrite(
        descriptor: ProviderDescriptor, install: FileInstall
    ) throws(ConfigFileError) -> PlannedWrite {
        let existing = try filesystem.readFile(at: install.path)
        if let existing, OwnedMarker.isOrcaManaged(existing) {
            return PlannedWrite(
                path: install.path, action: .skipOrcaManaged,
                diff: "skip: Orca-managed content preserved",
                backupPath: nil)
        }
        let next = try mergedContent(descriptor: descriptor, install: install, existing: existing)
        if existing == nil || existing?.isEmpty == true {
            return PlannedWrite(
                path: install.path, action: .create,
                diff: Self.lineDiff(old: nil, new: next),
                backupPath: Self.backupPath(for: install.path))
        }
        if existing == next {
            return PlannedWrite(
                path: install.path, action: .unchanged, diff: "",
                backupPath: nil)
        }
        return PlannedWrite(
            path: install.path,
            action: install.mergesJSON ? .mergeJSON : .update,
            diff: Self.lineDiff(old: existing, new: next),
            backupPath: Self.backupPath(for: install.path))
    }

    private func mergedContent(
        descriptor: ProviderDescriptor, install: FileInstall, existing: String?
    ) throws(ConfigFileError) -> String {
        if !install.mergesJSON, let existing, !existing.isEmpty, existing != install.content {
            // A sidecar filename alone does not establish ownership. Changed
            // sidecars are preserved for deliberate review, even with a marker.
            throw ConfigFileError.invalidData(path: install.path)
        }
        if install.mergesJSON, let existing, !existing.isEmpty {
            return try Self.mergedJSONContent(
                existing: existing, install: install, path: install.path)
        }
        return install.content
    }

    /// Merges install.content's top-level owned keys into existing JSON,
    /// preserving every unknown existing key. Refuses (throws `invalidData`)
    /// when existing shared JSON cannot parse as an object — never replaces.
    static func mergedJSONContent(
        existing: String, install: FileInstall, path: String
    ) throws(ConfigFileError) -> String {
        guard let existingData = existing.data(using: .utf8),
            let existingObject = try? JSONSerialization.jsonObject(with: existingData)
                as? [String: Any],
            let patchData = install.content.data(using: .utf8),
            let patchObject = try? JSONSerialization.jsonObject(with: patchData)
                as? [String: Any]
        else {
            throw ConfigFileError.invalidData(path: path)
        }
        func merge(_ base: [String: Any], _ patch: [String: Any]) throws -> [String: Any] {
            var result = base
            for (key, value) in patch {
                if let old = base[key], let oldObject = old as? [String: Any], let patchObject = value as? [String: Any] {
                    result[key] = try merge(oldObject, patchObject)
                } else if let old = base[key], !Self.equalJSON(old, value) {
                    throw ConfigFileError.invalidData(path: path)
                } else { result[key] = value }
            }
            return result
        }
        let merged: [String: Any]
        do { merged = try merge(existingObject, patchObject) }
        catch { throw ConfigFileError.invalidData(path: path) }
        guard let mergedData = try? JSONSerialization.data(
            withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: mergedData, encoding: .utf8)
        else {
            throw ConfigFileError.invalidData(path: path)
        }
        return text + "\n"
    }

    /// What install wrote, given the pre-install backup content. Used for
    /// exact-state comparison: restore the backup only when current is
    /// byte-identical to this.
    private func expectedInstalledContent(
        descriptor: ProviderDescriptor, install: FileInstall,
        backupContent: String
    ) throws(ConfigFileError) -> String {
        _ = descriptor
        if install.mergesJSON {
            if backupContent.isEmpty {
                return install.content
            }
            return try Self.mergedJSONContent(
                existing: backupContent, install: install, path: install.path)
        }
        return install.content
    }

    /// True when text parses as a JSON object.
    static func isJSONObject(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            object is [String: Any]
        else { return false }
        return true
    }

    /// An exact structured provider marker proves only entries matching the
    /// descriptor, never an entire key prefix or a changed nested hook.
    /// Three-way pruning restores original leaves and preserves later edits.
    static func prunedOwnedJSON(
        content: String, provider: String, install: FileInstall, originalContent: String? = nil
    ) -> String? {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["camlidOwned"] as? String == OwnedMarker.text(for: provider),
              let patchData = install.content.data(using: .utf8),
              let installed = try? JSONSerialization.jsonObject(with: patchData) as? [String: Any] else { return nil }
        let original = originalContent.flatMap { $0.data(using: .utf8) }.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        } ?? [:]
        var pruned = object
        for (key, ownedValue) in installed {
            if let value = restoreOwned(current: object[key], installed: ownedValue, original: original[key]) {
                pruned[key] = value
            } else { pruned.removeValue(forKey: key) }
        }
        guard !equalJSON(object, pruned),
              let result = try? JSONSerialization.data(withJSONObject: pruned, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: result, encoding: .utf8) else { return nil }
        return text + "\n"
    }

    private static func restoreOwned(current: Any?, installed: Any, original: Any?) -> Any? {
        guard let current else { return nil }
        if equalJSON(current, installed) { return original }
        guard let currentObject = current as? [String: Any], let installedObject = installed as? [String: Any] else {
            return current // Changed scalars/arrays cannot be attributed safely.
        }
        let originalObject = original as? [String: Any] ?? [:]
        var next = currentObject
        for (key, ownedValue) in installedObject {
            if let value = restoreOwned(current: currentObject[key], installed: ownedValue, original: originalObject[key]) { next[key] = value }
            else { next.removeValue(forKey: key) }
        }
        return next.isEmpty && original == nil ? nil : next
    }
    private static func equalJSON(_ left: Any, _ right: Any) -> Bool {
        guard let one = try? JSONSerialization.data(withJSONObject: left, options: [.sortedKeys, .fragmentsAllowed]),
              let two = try? JSONSerialization.data(withJSONObject: right, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
        return one == two
    }

    /// Removes only owned-marker-delimited lines, preserving all other lines.
    /// Returns nil when no owned marker line exists.
    static func prunedOwnedLines(content: String, provider: String) -> String? {
        let marker = OwnedMarker.text(for: provider)
        let lines = content.components(separatedBy: "\n")
        guard lines.contains(where: { $0.contains(marker) }) else { return nil }
        let kept = lines.filter { !$0.contains(marker) }
        var text = kept.joined(separator: "\n")
        // Preserve trailing newline convention when the original had one.
        if content.hasSuffix("\n"), !text.hasSuffix("\n"), !text.isEmpty {
            text += "\n"
        }
        return text
    }

    /// Simple line diff: common prefix/suffix elided, middle marked -/+.
    public static func lineDiff(old: String?, new: String) -> String {
        let oldLines = old?.components(separatedBy: "\n") ?? []
        let newLines = new.components(separatedBy: "\n")
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count,
            oldLines[prefix] == newLines[prefix]
        {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLines.count - prefix, suffix < newLines.count - prefix,
            oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix]
        {
            suffix += 1
        }
        var out: [String] = ["--- existing", "+++ planned"]
        for line in oldLines.prefix(prefix) { out.append("  \(line)") }
        for line in oldLines.dropFirst(prefix).dropLast(suffix) { out.append("- \(line)") }
        for line in newLines.dropFirst(prefix).dropLast(suffix) { out.append("+ \(line)") }
        for line in newLines.suffix(suffix) { out.append("  \(line)") }
        return out.joined(separator: "\n")
    }
}
