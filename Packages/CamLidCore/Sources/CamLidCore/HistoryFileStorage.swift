import Darwin
import Foundation

/// Private, bounded JSONL history. Failures are observable, never reported as
/// successful deletion. Lock protects all file operations and diagnostics.
public final class FileHistoryStorage: HistoryStorage, @unchecked Sendable {
    /// `~/Library/Application Support/CamLid/History`: the history file and the saved settings live here.
    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("CamLid/History", isDirectory: true)
    }

    private let lock = NSLock()
    private let directory: URL
    private let baseName: String
    private let maxBytes: Int
    private var skippedLines = 0
    private var operationError: String?

    public init(directory: URL, baseName: String = "camlid-history", maxBytes: Int = ActivityStore.defaultMaxBytes) {
        self.directory = directory
        self.baseName = baseName
        self.maxBytes = max(1_024, maxBytes)
    }
    private var perFileCap: Int { maxBytes / 2 }
    private var activeURL: URL { directory.appendingPathComponent("\(baseName).jsonl") }
    private var rotatedURL: URL { directory.appendingPathComponent("\(baseName).1.jsonl") }

    public func skippedCorruptLineCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return skippedLines
    }
    public func lastOperationError() -> String? {
        lock.lock(); defer { lock.unlock() }
        return operationError
    }

    public func append(_ record: StoredTransition) {
        lock.lock(); defer { lock.unlock() }
        operationError = nil
        do {
            let line = try JSONEncoder().encode(record) + Data([0x0A])
            guard line.count <= perFileCap else { operationError = "recordTooLarge"; return }
            try prepareDirectory()
            let size = try fileSize(activeURL)
            if size > perFileCap - line.count {
                if try inspectFile(rotatedURL) != nil {
                    try checkRegularFile(rotatedURL)
                    try FileManager.default.removeItem(at: rotatedURL)
                }
                try checkRegularFile(activeURL)
                try FileManager.default.moveItem(at: activeURL, to: rotatedURL)
            }
            if try inspectFile(activeURL) == nil {
                guard FileManager.default.createFile(atPath: activeURL.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else {
                    operationError = "createFailed"; return
                }
            }
            try appendWithoutFollowingSymlink(line, to: activeURL)
        } catch { operationError = diagnostic(for: error, fallback: "appendFailed") }
    }

    public func load() -> [StoredTransition] {
        lock.lock(); defer { lock.unlock() }
        operationError = nil
        return loadLocked()
    }

    @discardableResult
    public func removeAll(where shouldRemove: @Sendable (StoredTransition) -> Bool) -> Int {
        lock.lock(); defer { lock.unlock() }
        operationError = nil
        var removed = 0
        // Each file replacement is atomic. On partial failure report only the
        // committed removals, plus the diagnostic; never erase then rebuild.
        for url in [rotatedURL, activeURL] {
            do {
                guard let metadata = try inspectFile(url) else { continue }
                guard metadata.size <= maxBytes else { throw HistoryStorageFailure.tooLarge }
                let (original, identity) = try readBounded(url)
                var kept = Data()
                var count = 0
                var hadCorruptLine = false
                for piece in original.split(separator: 0x0A) {
                    if let record = try? JSONDecoder().decode(StoredTransition.self, from: Data(piece)) {
                        if shouldRemove(record) { count += 1 }
                        else { kept.append(contentsOf: piece); kept.append(0x0A) }
                    } else {
                        hadCorruptLine = true
                        kept.append(contentsOf: piece); kept.append(0x0A)
                    }
                }
                if count > 0 {
                    try ensurePathStillMatches(url, identity: identity)
                    try kept.write(to: url, options: .atomic)
                    removed += count
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
                if hadCorruptLine, operationError == nil { operationError = "historyCorruptLinesRetained" }
            } catch {
                operationError = diagnostic(for: error, fallback: "deleteFailed")
                break
            }
        }
        return removed
    }

    @discardableResult
    public func clear() -> Int {
        lock.lock(); defer { lock.unlock() }
        operationError = nil
        var removed = 0
        for url in [rotatedURL, activeURL] {
            do {
                guard let metadata = try inspectFile(url) else { continue }
                if metadata.size > maxBytes {
                    try unlinkOwnedFile(url, matching: metadata.identity)
                    if operationError == nil { operationError = "historyCountUnknown" }
                    continue
                }

                let (data, identity) = try readBounded(url)
                var count = 0
                var hadCorruptLine = false
                for piece in data.split(separator: 0x0A) {
                    if (try? JSONDecoder().decode(StoredTransition.self, from: Data(piece))) != nil {
                        count += 1
                    } else {
                        hadCorruptLine = true
                    }
                }
                try unlinkOwnedFile(url, matching: identity)
                removed += count
                if hadCorruptLine, operationError == nil { operationError = "historyCountUnknown" }
            } catch {
                operationError = diagnostic(for: error, fallback: "deleteFailed")
                break
            }
        }
        return removed
    }

    private func loadLocked() -> [StoredTransition] {
        var out: [StoredTransition] = []
        skippedLines = 0 // Count corrupt lines in this snapshot, not rereads.
        for url in [rotatedURL, activeURL] {
            do {
                guard try inspectFile(url) != nil else { continue }
                let (data, _) = try readBounded(url)
                for piece in data.split(separator: 0x0A) {
                    if let record = try? JSONDecoder().decode(StoredTransition.self, from: Data(piece)) { out.append(record) }
                    else { skippedLines += 1 }
                }
            } catch {
                operationError = diagnostic(for: error, fallback: "readFailed")
            }
        }
        return out
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw HistoryStorageFailure.unsafeFile }
    }

    private func appendWithoutFollowingSymlink(_ data: Data, to url: URL) throws {
        let fd = try openFile(url, flags: O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0 else { throw HistoryStorageFailure.readFailed }
        let identity = try verifiedIdentity(info)
        guard isRegularFile(info.st_mode) else { throw HistoryStorageFailure.unsafeFile }
        try ensurePathStillMatches(url, identity: identity)

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(fd, baseAddress.advanced(by: written), rawBuffer.count - written)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { throw HistoryStorageFailure.writeFailed }
                written += result
            }
        }
        guard Darwin.fsync(fd) == 0 else { throw HistoryStorageFailure.writeFailed }
        var final = stat()
        guard Darwin.fstat(fd, &final) == 0 else { throw HistoryStorageFailure.writeFailed }
        let finalIdentity = try verifiedIdentity(final)
        guard finalIdentity.sameObject(as: identity) else { throw HistoryStorageFailure.changed }
        try ensurePathStillMatches(url, identity: finalIdentity)
    }

    private func readBounded(_ url: URL) throws -> (Data, FileIdentity) {
        let fd = try openFile(url, flags: O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        defer { _ = Darwin.close(fd) }
        var initial = stat()
        guard Darwin.fstat(fd, &initial) == 0 else { throw HistoryStorageFailure.readFailed }
        let identity = try verifiedIdentity(initial)
        guard isRegularFile(initial.st_mode) else { throw HistoryStorageFailure.unsafeFile }
        guard initial.st_size >= 0, initial.st_size <= maxBytes else { throw HistoryStorageFailure.tooLarge }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let remaining = maxBytes - data.count
            let readLimit = min(buffer.count, remaining == Int.max ? buffer.count : remaining + 1)
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fd, rawBuffer.baseAddress, readLimit)
            }
            if count == 0 { break }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw HistoryStorageFailure.readFailed }
            guard data.count <= maxBytes - count else { throw HistoryStorageFailure.tooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }

        var final = stat()
        guard Darwin.fstat(fd, &final) == 0 else { throw HistoryStorageFailure.readFailed }
        let finalIdentity = try verifiedIdentity(final)
        guard finalIdentity == identity, final.st_size == data.count else {
            throw HistoryStorageFailure.changed
        }
        guard data.count <= maxBytes else { throw HistoryStorageFailure.tooLarge }
        return (data, identity)
    }

    private func openFile(_ url: URL, flags: Int32) throws -> Int32 {
        let fd = url.path.withCString { Darwin.open($0, flags) }
        guard fd >= 0 else {
            if errno == ELOOP { throw HistoryStorageFailure.unsafeFile }
            if errno == ENOENT { throw HistoryStorageFailure.changed }
            throw HistoryStorageFailure.readFailed
        }
        return fd
    }

    private func inspectFile(_ url: URL) throws -> FileMetadata? {
        var info = stat()
        let result = url.path.withCString { Darwin.lstat($0, &info) }
        if result != 0 {
            if errno == ENOENT { return nil }
            throw HistoryStorageFailure.readFailed
        }
        guard isRegularFile(info.st_mode), info.st_uid == geteuid() else { throw HistoryStorageFailure.unsafeFile }
        guard info.st_size >= 0 else { throw HistoryStorageFailure.readFailed }
        return FileMetadata(identity: try verifiedIdentity(info), size: Int(info.st_size))
    }

    private func verifiedIdentity(_ info: stat) throws -> FileIdentity {
        guard isRegularFile(info.st_mode), info.st_uid == geteuid(), info.st_size >= 0 else {
            throw HistoryStorageFailure.unsafeFile
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino, size: info.st_size)
    }

    private func ensurePathStillMatches(_ url: URL, identity: FileIdentity) throws {
        guard let current = try inspectFile(url), current.identity == identity else {
            throw HistoryStorageFailure.changed
        }
    }

    private func unlinkOwnedFile(_ url: URL, matching identity: FileIdentity) throws {
        try ensurePathStillMatches(url, identity: identity)
        let result = url.path.withCString { Darwin.unlink($0) }
        guard result == 0 else { throw HistoryStorageFailure.deleteFailed }
    }

    private func checkRegularFile(_ url: URL) throws {
        guard try inspectFile(url) != nil else { throw HistoryStorageFailure.changed }
    }

    private func fileSize(_ url: URL) throws -> Int {
        guard let metadata = try inspectFile(url) else { return 0 }
        return metadata.size
    }

    private func isRegularFile(_ mode: mode_t) -> Bool {
        mode & mode_t(S_IFMT) == mode_t(S_IFREG)
    }

    private func diagnostic(for error: Error, fallback: String) -> String {
        switch error {
        case HistoryStorageFailure.tooLarge: return "historyTooLarge"
        case HistoryStorageFailure.unsafeFile: return "unsafeHistoryFile"
        case HistoryStorageFailure.changed: return "historyChanged"
        case HistoryStorageFailure.deleteFailed: return "deleteFailed"
        case HistoryStorageFailure.readFailed: return "readFailed"
        case HistoryStorageFailure.writeFailed: return "appendFailed"
        default: return fallback
        }
    }
}

private struct FileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t

    func sameObject(as other: Self) -> Bool {
        device == other.device && inode == other.inode
    }
}

private struct FileMetadata {
    let identity: FileIdentity
    let size: Int
}

private enum HistoryStorageFailure: Error {
    case unsafeFile
    case tooLarge
    case readFailed
    case writeFailed
    case deleteFailed
    case changed
}
