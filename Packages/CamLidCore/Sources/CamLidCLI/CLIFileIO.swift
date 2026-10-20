import Foundation
import Darwin
import CamLidCore

/// Real transport plumbing for the `camlid` executable (F03).
///
/// The library-level `CommandContext.files` / `stdinData` map stays as an
/// in-memory seam for unit tests. The executable wires the disk/stdin
/// implementations below so config/simulate/event actually touch disk/stdin
/// and `logs export` actually writes bytes. All bounds are enforced before
/// any channel use.
public enum CLIFileReadError: Error, Sendable, Equatable {
    case notFound(path: String)
    case unreadable(path: String, detail: String)
    case tooLarge(path: String, size: Int)
}

public protocol CLIFileReader: Sendable {
    func readFile(atPath path: String) throws -> Data
}

public protocol CLIStdinReader: Sendable {
    func readStdin() -> Data?
}

public protocol CLIAtomicWriter: Sendable {
    func fileExists(atPath path: String) -> Bool
    func writeAtomically(_ data: Data, toPath path: String) throws
    func writeAtomically(_ data: Data, toPath path: String, overwrite: Bool) throws
}

public extension CLIAtomicWriter {
    func writeAtomically(_ data: Data, toPath path: String, overwrite: Bool) throws {
        if !overwrite && fileExists(atPath: path) { throw CLIFileWriteError.overwriteRefused(path: path) }
        try writeAtomically(data, toPath: path)
    }
}

public enum CLIFileWriteError: Error, Sendable, Equatable {
    case overwriteRefused(path: String)
    case writeFailed(path: String, detail: String)
}

/// Upper bound for config/scenario file reads. Events use the 64 KiB
/// `BoundedPayload` bound separately.
public enum CLIFileBounds {
    public static let maxFileBytes = 1_048_576
}

public struct DiskFileReader: CLIFileReader, Sendable {
    public init() {}
    public func readFile(atPath path: String) throws -> Data {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIFileReadError.notFound(path: path)
        }
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CLIFileReadError.unreadable(path: path, detail: String(describing: error))
        }
        guard data.count <= CLIFileBounds.maxFileBytes else {
            throw CLIFileReadError.tooLarge(path: path, size: data.count)
        }
        return data
    }
}

public struct DiskAtomicWriter: CLIAtomicWriter, Sendable {
    public init() {}
    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    public func writeAtomically(_ data: Data, toPath path: String, overwrite: Bool) throws {
        if overwrite { try writeAtomically(data, toPath: path); return }
        let target = URL(fileURLWithPath: path)
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".camlid-export-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            // One atomic commit refuses a destination created after any prior
            // existence check. No check-then-overwrite race.
            guard renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw CLIFileWriteError.overwriteRefused(path: path) }
                throw CLIFileWriteError.writeFailed(path: path, detail: "atomicCommitFailed")
            }
        } catch let error as CLIFileWriteError { throw error }
        catch { throw CLIFileWriteError.writeFailed(path: path, detail: "exportWriteFailed") }
    }
    public func writeAtomically(_ data: Data, toPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CLIFileWriteError.writeFailed(path: path, detail: String(describing: error))
        }
    }
}

public struct StandardInputReader: CLIStdinReader, Sendable {
    public init() {}
    public func readStdin() -> Data? {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return data
    }
}

/// In-memory file store for unit tests: backs both reader and writer without
/// touching disk. Real-tempdir coverage uses `DiskFileReader` /
/// `DiskAtomicWriter` directly (see AuditCLITests).
public final class InMemoryFileStore: CLIFileReader, CLIAtomicWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data]

    public init(files: [String: String] = [:]) {
        var mapped: [String: Data] = [:]
        for (key, value) in files {
            mapped[key] = Data(value.utf8)
        }
        self.files = mapped
    }

    public init(dataFiles: [String: Data]) {
        self.files = dataFiles
    }

    public func readFile(atPath path: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[path] else {
            throw CLIFileReadError.notFound(path: path)
        }
        guard data.count <= CLIFileBounds.maxFileBytes else {
            throw CLIFileReadError.tooLarge(path: path, size: data.count)
        }
        return data
    }

    public func fileExists(atPath path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[path] != nil
    }

    public func writeAtomically(_ data: Data, toPath path: String) throws {
        lock.lock(); defer { lock.unlock() }
        files[path] = data
    }

    public func snapshotStrings() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: String] = [:]
        for (key, value) in files {
            out[key] = String(data: value, encoding: .utf8) ?? ""
        }
        return out
    }

    public func snapshotData() -> [String: Data] {
        lock.lock(); defer { lock.unlock() }
        return files
    }
}

public struct InMemoryStdinReader: CLIStdinReader, Sendable {
    public var data: Data?
    public init(data: Data?) {
        self.data = data
    }
    public func readStdin() -> Data? {
        data
    }
}
