import Foundation
import CryptoKit
import Darwin

/// Recovery intent, not an authenticated owner token or a power capability.
public struct JournalEntry: Codable, Equatable, Sendable {
    public enum Intent: String, Codable, Sendable {
        case enableLidOverride, restoreLidPolicy
    }
    public enum Disposition: String, Codable, Sendable {
        case pending, acknowledged, unresolved
    }

    public let revision: UInt64
    public let sessionID: String
    public let ownerIdentity: String
    public let bootID: String
    public let generation: UInt64
    public let operationID: String
    public let intent: Intent
    public let disposition: Disposition
    /// Absolute continuous-clock deadline, valid only for the recorded boot.
    public let continuousDeadlineNanos: UInt64

    public init(
        revision: UInt64, sessionID: String, ownerIdentity: String, bootID: String,
        generation: UInt64, operationID: String, intent: Intent,
        disposition: Disposition, continuousDeadlineNanos: UInt64
    ) {
        self.revision = revision
        self.sessionID = sessionID
        self.ownerIdentity = ownerIdentity
        self.bootID = bootID
        self.generation = generation
        self.operationID = operationID
        self.intent = intent
        self.disposition = disposition
        self.continuousDeadlineNanos = continuousDeadlineNanos
    }
}

public enum JournalFailure: Error, Equatable {
    case revisionConflict
    case invalidEntry
    case busy
    case corrupt
    case unsafeStorage
    case tooLarge(limit: Int)
    case unsupportedSchema(Int)
    case io(operation: String, code: Int32)
    /// Publication may have happened; a durable result was not acknowledged.
    case publicationUncertain(operation: String, code: Int32)
}

/// Standalone macOS storage seam. Cooperative file locks are not IPC peer
/// authentication or ownership of any power resource. Confine each instance
/// to one execution context; filesystem calls can still block.
public final class DurableRecoveryJournal {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let entry: JournalEntry
        let digest: String
    }

    public static let maximumBytes = 65_536
    private let directoryFD: Int32
    private let systemCalls: any JournalSystemCalls

    private func isValid(_ entry: JournalEntry) -> Bool {
        entry.revision > 0 && entry.generation > 0 && entry.continuousDeadlineNanos > 0 &&
        !entry.sessionID.isEmpty && !entry.ownerIdentity.isEmpty &&
        !entry.bootID.isEmpty && !entry.operationID.isEmpty
    }

    private func encoded(_ entry: JournalEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entry)
    }

    private func digest(_ entry: JournalEntry) throws -> String {
        SHA256.hash(data: try encoded(entry)).map { String(format: "%02x", $0) }.joined()
    }

    public convenience init(directory: URL) throws {
        try self.init(directory: directory, systemCalls: DarwinJournalSystemCalls())
    }

    @_spi(FaultInjection)
    public init(directory: URL, systemCalls: any JournalSystemCalls) throws {
        self.systemCalls = systemCalls
        guard directory.isFileURL else { throw JournalFailure.unsafeStorage }
        if Darwin.mkdir(directory.path, 0o700) != 0, errno != EEXIST {
            throw JournalFailure.io(operation: "mkdir", code: errno)
        }
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw JournalFailure.unsafeStorage }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 else {
            Darwin.close(fd)
            throw JournalFailure.unsafeStorage
        }
        do {
            guard systemCalls.synchronize(fd) == 0 else {
                throw JournalFailure.io(operation: "initialDirectorySync", code: errno)
            }
            let parentFD = Darwin.open(directory.deletingLastPathComponent().path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard parentFD >= 0 else { throw JournalFailure.io(operation: "openParent", code: errno) }
            defer { Darwin.close(parentFD) }
            var linked = stat()
            guard fstatat(parentFD, directory.lastPathComponent, &linked, AT_SYMLINK_NOFOLLOW) == 0,
                  linked.st_dev == info.st_dev, linked.st_ino == info.st_ino else {
                throw JournalFailure.unsafeStorage
            }
            guard systemCalls.synchronize(parentFD) == 0 else {
                throw JournalFailure.io(operation: "parentDirectorySync", code: errno)
            }
        } catch {
            Darwin.close(fd)
            throw error
        }
        directoryFD = fd
    }

    deinit { Darwin.close(directoryFD) }

    private func withLock<T>(_ mode: Int32, _ body: () throws -> T) throws -> T {
        var directory = stat()
        guard fstat(directoryFD, &directory) == 0, directory.st_uid == geteuid(), directory.st_nlink > 0,
              directory.st_mode & S_IFMT == S_IFDIR, directory.st_mode & 0o777 == 0o700 else {
            throw JournalFailure.unsafeStorage
        }
        let lockFD = openat(directoryFD, ".journal.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard lockFD >= 0 else {
            if errno == ELOOP { throw JournalFailure.unsafeStorage }
            throw JournalFailure.io(operation: "openLock", code: errno)
        }
        defer { Darwin.close(lockFD) }
        var lockInfo = stat()
        guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_uid == geteuid(), lockInfo.st_nlink == 1,
              lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_mode & 0o777 == 0o600 else {
            throw JournalFailure.unsafeStorage
        }
        guard flock(lockFD, mode | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw JournalFailure.busy }
            throw JournalFailure.io(operation: "lock", code: errno)
        }
        defer { flock(lockFD, LOCK_UN) }
        return try body()
    }

    public func load() throws -> JournalEntry? {
        try withLock(LOCK_SH) { try loadLocked() }
    }

    private func loadLocked() throws -> JournalEntry? {
        let fd = openat(directoryFD, "recovery.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw JournalFailure.unsafeStorage }
            throw JournalFailure.io(operation: "openJournal", code: errno)
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o777 == 0o600 else {
            throw JournalFailure.unsafeStorage
        }
        guard info.st_size >= 0, info.st_size <= Self.maximumBytes else {
            throw JournalFailure.tooLarge(limit: Self.maximumBytes)
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw JournalFailure.io(operation: "read", code: errno) }
            if count == 0 { break }
            guard data.count + count <= Self.maximumBytes else {
                throw JournalFailure.tooLarge(limit: Self.maximumBytes)
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == 1 else {
                throw JournalFailure.unsupportedSchema(envelope.schemaVersion)
            }
            guard isValid(envelope.entry), try envelope.digest == digest(envelope.entry) else {
                throw JournalFailure.corrupt
            }
            return envelope.entry
        } catch let failure as JournalFailure {
            throw failure
        } catch {
            throw JournalFailure.corrupt
        }
    }

    /// nil means creation only; an expected revision means compare-and-replace.
    public func commit(_ entry: JournalEntry, replacing expectedRevision: UInt64?) throws {
        try withLock(LOCK_EX) { try commitLocked(entry, replacing: expectedRevision) }
    }

    private func commitLocked(_ entry: JournalEntry, replacing expectedRevision: UInt64?) throws {
        let previous = try loadLocked()
        guard previous?.revision == expectedRevision else { throw JournalFailure.revisionConflict }
        let next = (expectedRevision ?? 0).addingReportingOverflow(1)
        guard !next.overflow, entry.revision == next.partialValue else {
            throw JournalFailure.revisionConflict
        }
        guard isValid(entry) else { throw JournalFailure.invalidEntry }
        // Bound raw string input before canonical encoding/hash allocation; the
        // envelope limit below also accounts for JSON escaping and metadata.
        var remaining = Self.maximumBytes
        for value in [entry.sessionID, entry.ownerIdentity, entry.bootID, entry.operationID] {
            let count = value.utf8.count
            guard count <= remaining else { throw JournalFailure.tooLarge(limit: Self.maximumBytes) }
            remaining -= count
        }
        let envelope = Envelope(schemaVersion: 1, entry: entry, digest: try digest(entry))
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= Self.maximumBytes else { throw JournalFailure.tooLarge(limit: Self.maximumBytes) }
        let temporaryName = ".journal-\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw JournalFailure.io(operation: "createTemporary", code: errno) }
        defer {
            Darwin.close(fd)
            unlinkat(directoryFD, temporaryName, 0)
        }
        guard fchmod(fd, 0o600) == 0 else { throw JournalFailure.io(operation: "chmodTemporary", code: errno) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw JournalFailure.corrupt }
            var offset = 0
            while offset < bytes.count {
                let count = systemCalls.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0, count <= bytes.count - offset else {
                    throw JournalFailure.io(operation: "write", code: count < 0 ? errno : EIO)
                }
                offset += count
            }
        }
        guard systemCalls.synchronize(fd) == 0 else { throw JournalFailure.io(operation: "fileSync", code: errno) }
        guard systemCalls.publish(directoryFD: directoryFD, temporaryName: temporaryName, finalName: "recovery.json") == 0 else {
            // A reported publication error need not prove the namespace was
            // untouched (for example, an indeterminate filesystem response).
            throw JournalFailure.publicationUncertain(operation: "publish", code: errno)
        }
        guard systemCalls.synchronize(directoryFD) == 0 else {
            throw JournalFailure.publicationUncertain(operation: "directorySync", code: errno)
        }
    }
}
