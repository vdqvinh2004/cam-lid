import Foundation
import Testing
import Darwin
import CryptoKit
@_spi(FaultInjection) import LidRecoveryJournal

@Suite("Experimental durable recovery journal", .serialized)
struct DurableRecoveryJournalTests {
    private func entry(revision: UInt64 = 1, disposition: JournalEntry.Disposition = .pending) -> JournalEntry {
        JournalEntry(
            revision: revision, sessionID: "session-a", ownerIdentity: "claimed-owner-a",
            bootID: "boot-a", generation: 1, operationID: "operation-a",
            intent: .restoreLidPolicy, disposition: disposition, continuousDeadlineNanos: 30_000_000_000
        )
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camlid-journal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("journal", isDirectory: true))
    }

    private struct FileSyncFailure: JournalSystemCalls {
        private let real = DarwinJournalSystemCalls()
        func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
            real.write(fd, bytes, count)
        }
        func synchronize(_ fd: Int32) -> Int32 {
            var info = stat()
            if fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG {
                errno = ENOSPC
                return -1
            }
            return real.synchronize(fd)
        }
        func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32 {
            real.publish(directoryFD: directoryFD, temporaryName: temporaryName, finalName: finalName)
        }
    }

    private struct ParentFlushFailure: JournalSystemCalls {
        let parentInode: UInt64
        private let real = DarwinJournalSystemCalls()
        func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
            real.write(fd, bytes, count)
        }
        func synchronize(_ fd: Int32) -> Int32 {
            var info = stat()
            if fstat(fd, &info) == 0, info.st_ino == parentInode {
                errno = ENOSPC
                return -1
            }
            return real.synchronize(fd)
        }
        func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32 {
            real.publish(directoryFD: directoryFD, temporaryName: temporaryName, finalName: finalName)
        }
    }

    @Test func parentDirectoryFlushFailurePreventsAdmission() throws {
        try withDirectory { directory in
            var parent = stat()
            #expect(stat(directory.deletingLastPathComponent().path, &parent) == 0)
            #expect(throws: JournalFailure.io(operation: "parentDirectorySync", code: ENOSPC)) {
                _ = try DurableRecoveryJournal(directory: directory,
                    systemCalls: ParentFlushFailure(parentInode: parent.st_ino))
            }
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("recovery.json").path))
        }
    }

    private final class FixtureBundleLocator: NSObject {}

    private func fixtureExecutable() throws -> URL {
        var directory = Bundle(for: FixtureBundleLocator.self).bundleURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("LidJournalFixture")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func launchFixture(_ args: [String], output: FileHandle? = nil) throws -> Process {
        let process = Process()
        process.executableURL = try fixtureExecutable()
        process.arguments = args
        process.standardOutput = output
        try process.run()
        return process
    }

    private func awaitCondition(_ predicate: () -> Bool) throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.executableRuntimeMismatch) }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private enum Fault: String {
        case diskFull, zeroWrite, rename, renameAfterPublication, directorySync, shortWrite, interruptedWrite
    }

    private final class FaultingCalls: JournalSystemCalls {
        let fault: Fault
        var armed = false
        private var interrupted = false
        private let real = DarwinJournalSystemCalls()
        init(_ fault: Fault) { self.fault = fault }
        func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
            if armed {
                if fault == .diskFull { errno = ENOSPC; return -1 }
                if fault == .zeroWrite { return 0 }
                if fault == .shortWrite { return real.write(fd, bytes, min(count, 7)) }
                if fault == .interruptedWrite, !interrupted {
                    interrupted = true
                    errno = EINTR
                    return -1
                }
            }
            return real.write(fd, bytes, count)
        }
        func synchronize(_ fd: Int32) -> Int32 {
            var info = stat()
            if armed, fault == .directorySync, fstat(fd, &info) == 0,
               info.st_mode & S_IFMT == S_IFDIR {
                errno = EIO
                return -1
            }
            return real.synchronize(fd)
        }
        func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32 {
            if armed, fault == .rename { errno = EIO; return -1 }
            if armed, fault == .renameAfterPublication {
                let result = real.publish(directoryFD: directoryFD, temporaryName: temporaryName, finalName: finalName)
                if result == 0 { errno = EIO; return -1 }
                return result
            }
            return real.publish(directoryFD: directoryFD, temporaryName: temporaryName, finalName: finalName)
        }
    }

    @Test(arguments: [Fault.diskFull, .zeroWrite, .rename])
    private func failureBeforePublicationPreservesPriorRecord(_ fault: Fault) throws {
        try withDirectory { directory in
            let original = try DurableRecoveryJournal(directory: directory)
            try original.commit(entry(), replacing: nil)
            let calls = FaultingCalls(fault)
            let failing = try DurableRecoveryJournal(directory: directory, systemCalls: calls)
            calls.armed = true
            let expected: JournalFailure = fault == .rename
                ? .publicationUncertain(operation: "publish", code: EIO)
                : .io(operation: "write", code: fault == .diskFull ? ENOSPC : EIO)
            #expect(throws: expected) {
                try failing.commit(entry(revision: 2, disposition: .unresolved), replacing: 1)
            }
            #expect(try original.load() == entry())
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(!names.contains { $0.hasSuffix(".tmp") })
        }
    }

    @Test func publicationErrorCannotPromiseThatNothingChanged() throws {
        try withDirectory { directory in
            let original = try DurableRecoveryJournal(directory: directory)
            try original.commit(entry(), replacing: nil)
            let calls = FaultingCalls(.renameAfterPublication)
            let failing = try DurableRecoveryJournal(directory: directory, systemCalls: calls)
            calls.armed = true
            #expect(throws: JournalFailure.publicationUncertain(operation: "publish", code: EIO)) {
                try failing.commit(entry(revision: 2, disposition: .unresolved), replacing: 1)
            }
            #expect(try original.load() == entry(revision: 2, disposition: .unresolved))
        }
    }

    @Test func postPublicationFlushFailureRemainsUncertain() throws {
        try withDirectory { directory in
            let original = try DurableRecoveryJournal(directory: directory)
            try original.commit(entry(), replacing: nil)
            let calls = FaultingCalls(.directorySync)
            let failing = try DurableRecoveryJournal(directory: directory, systemCalls: calls)
            calls.armed = true
            #expect(throws: JournalFailure.publicationUncertain(operation: "directorySync", code: EIO)) {
                try failing.commit(entry(revision: 2, disposition: .unresolved), replacing: 1)
            }
            // Visibility after failed flush is not a durability acknowledgment.
            #expect(try original.load() == entry(revision: 2, disposition: .unresolved))
            #expect(throws: JournalFailure.revisionConflict) {
                try original.commit(entry(revision: 2), replacing: 1)
            }
        }
    }

    @Test(arguments: [Fault.shortWrite, .interruptedWrite])
    private func completeRecordSurvivesShortOrInterruptedWrites(_ fault: Fault) throws {
        try withDirectory { directory in
            let calls = FaultingCalls(fault)
            let journal = try DurableRecoveryJournal(directory: directory, systemCalls: calls)
            calls.armed = true
            try journal.commit(entry(), replacing: nil)
            #expect(try DurableRecoveryJournal(directory: directory).load() == entry())
        }
    }

    @Test func restartInANewProcessReadsTheWholeIntent() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(disposition: .unresolved), replacing: nil)
            let outputURL = directory.deletingLastPathComponent().appendingPathComponent("output.json")
            #expect(FileManager.default.createFile(atPath: outputURL.path, contents: nil,
                                                  attributes: [.posixPermissions: 0o600]))
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            let reader = try launchFixture(["load", directory.path], output: output)
            defer { if reader.isRunning { reader.terminate() } }
            try awaitCondition { !reader.isRunning }
            #expect(reader.terminationStatus == 0)
            let loaded = try JSONDecoder().decode(JournalEntry.self, from: Data(contentsOf: outputURL))
            #expect(loaded == entry(disposition: .unresolved))
        }
    }

    @Test func killedWriterLeavesPriorIntentAndReleasesItsLock() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            let signals = directory.deletingLastPathComponent().appendingPathComponent("signals")
            try FileManager.default.createDirectory(at: signals, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let writer = try launchFixture(["pause", directory.path, signals.path])
            defer { if writer.isRunning { writer.terminate() } }
            try awaitCondition { FileManager.default.fileExists(atPath: signals.appendingPathComponent("paused").path) }
            #expect(kill(writer.processIdentifier, SIGKILL) == 0)
            try awaitCondition { !writer.isRunning }
            #expect(writer.terminationReason == .uncaughtSignal)
            let restarted = try DurableRecoveryJournal(directory: directory)
            #expect(try restarted.load() == entry())
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(names.contains { $0.hasSuffix(".tmp") }) // never promoted as an authoritative intent
            try restarted.commit(entry(revision: 2, disposition: .unresolved), replacing: 1)
            #expect(try restarted.load() == entry(revision: 2, disposition: .unresolved))
        }
    }

    @Test(arguments: ["empty", "truncated", "unknownIntent"])
    func malformedDiskRecordIsNotAnEmptyJournal(_ kind: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            let file = directory.appendingPathComponent("recovery.json")
            let original = try String(contentsOf: file, encoding: .utf8)
            let broken = kind == "empty" ? "" : kind == "truncated" ? "{" :
                original.replacingOccurrences(of: "restoreLidPolicy", with: "unknownIntent")
            try Data(broken.utf8).write(to: file)
            #expect(throws: JournalFailure.corrupt) { try journal.load() }
            #expect(throws: JournalFailure.corrupt) { try journal.commit(entry(), replacing: nil) }
        }
    }

    @Test func futureSchemaIsNotRewritten() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            let file = directory.appendingPathComponent("recovery.json")
            var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            envelope["schemaVersion"] = 2
            try JSONSerialization.data(withJSONObject: envelope).write(to: file)
            #expect(throws: JournalFailure.unsupportedSchema(2)) { try journal.load() }
            #expect(throws: JournalFailure.unsupportedSchema(2)) {
                try journal.commit(entry(revision: 2), replacing: 1)
            }
        }
    }

    @Test func oversizedDiskRecordIsRejectedBeforeDecoding() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            try Data(repeating: 0, count: DurableRecoveryJournal.maximumBytes + 1)
                .write(to: directory.appendingPathComponent("recovery.json"))
            #expect(throws: JournalFailure.tooLarge(limit: DurableRecoveryJournal.maximumBytes)) {
                try journal.load()
            }
        }
    }

    @Test func oversizedIntentCannotReplaceAnExistingFault() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(disposition: .unresolved), replacing: nil)
            let huge = JournalEntry(revision: 2, sessionID: "session-a",
                ownerIdentity: String(repeating: "x", count: DurableRecoveryJournal.maximumBytes + 1),
                bootID: "boot-a", generation: 1, operationID: "operation-a", intent: .restoreLidPolicy,
                disposition: .pending, continuousDeadlineNanos: 30_000_000_000)
            #expect(throws: JournalFailure.tooLarge(limit: DurableRecoveryJournal.maximumBytes)) {
                try journal.commit(huge, replacing: 1)
            }
            #expect(try journal.load() == entry(disposition: .unresolved))
        }
    }

    @Test func validChecksumIsNotAuthentication() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            let forged = JournalEntry(revision: 1, sessionID: "different-session",
                ownerIdentity: "untrusted-claimed-owner", bootID: "different-boot", generation: 99,
                operationID: "forged", intent: .enableLidOverride, disposition: .acknowledged,
                continuousDeadlineNanos: 1)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(forged)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let envelope: [String: Any] = ["schemaVersion": 1, "digest": hash,
                "entry": try JSONSerialization.jsonObject(with: data)]
            try JSONSerialization.data(withJSONObject: envelope)
                .write(to: directory.appendingPathComponent("recovery.json"))
            #expect(try journal.load() == forged) // deliberate limitation, not successful caller authentication
        }
    }

    @Test(arguments: ["session", "owner", "boot", "generation", "operation", "deadline"])
    func malformedIntentCannotBeCommitted(_ field: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            let invalid = JournalEntry(revision: 1,
                sessionID: field == "session" ? "" : "session-a",
                ownerIdentity: field == "owner" ? "" : "claimed-owner-a",
                bootID: field == "boot" ? "" : "boot-a",
                generation: field == "generation" ? 0 : 1,
                operationID: field == "operation" ? "" : "operation-a",
                intent: .restoreLidPolicy, disposition: .pending,
                continuousDeadlineNanos: field == "deadline" ? 0 : 30_000_000_000)
            #expect(throws: JournalFailure.invalidEntry) {
                try journal.commit(invalid, replacing: nil)
            }
            #expect(try journal.load() == nil)
        }
    }

    @Test func anotherProcessCannotCommitWhilePublicationIsPending() throws {
        try withDirectory { directory in
            let original = try DurableRecoveryJournal(directory: directory)
            try original.commit(entry(), replacing: nil)
            let signals = directory.deletingLastPathComponent().appendingPathComponent("signals")
            try FileManager.default.createDirectory(at: signals, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let paused = try launchFixture(["pause", directory.path, signals.path])
            defer { if paused.isRunning { paused.terminate() } }
            try awaitCondition { FileManager.default.fileExists(atPath: signals.appendingPathComponent("paused").path) }
            let contender = try launchFixture(["update", directory.path])
            defer { if contender.isRunning { contender.terminate() } }
            try awaitCondition { !contender.isRunning }
            #expect(contender.terminationStatus == 4) // busy, not a lost update or an indefinite lock wait
            try Data().write(to: signals.appendingPathComponent("resume"))
            try awaitCondition { !paused.isRunning }
            #expect(paused.terminationStatus == 0)
            #expect(try original.load()?.operationID == "pause")
        }
    }

    @Test(arguments: ["symlink", "hardlink", "shared"])
    func unsafeRecordIsNotReadOrOverwritten(_ kind: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            let file = directory.appendingPathComponent("recovery.json")
            if kind == "shared" {
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            } else {
                let foreign = directory.deletingLastPathComponent().appendingPathComponent("foreign.json")
                try FileManager.default.moveItem(at: file, to: foreign)
                if kind == "symlink" {
                    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
                } else {
                    try FileManager.default.linkItem(at: foreign, to: file)
                }
            }
            #expect(throws: JournalFailure.unsafeStorage) { try journal.load() }
            #expect(throws: JournalFailure.unsafeStorage) {
                try journal.commit(entry(revision: 2), replacing: 1)
            }
        }
    }

    @Test func failedFileFlushRetainsPreviousIntent() throws {
        try withDirectory { directory in
            let original = try DurableRecoveryJournal(directory: directory)
            try original.commit(entry(), replacing: nil)
            let failing = try DurableRecoveryJournal(directory: directory, systemCalls: FileSyncFailure())
            #expect(throws: JournalFailure.io(operation: "fileSync", code: ENOSPC)) {
                try failing.commit(entry(revision: 2, disposition: .unresolved), replacing: 1)
            }
            #expect(try DurableRecoveryJournal(directory: directory).load() == entry())
        }
    }

    @Test(arguments: [true, false])
    func unsafeDirectoryIsRejected(_ symlink: Bool) throws {
        try withDirectory { directory in
            if symlink {
                let target = directory.deletingLastPathComponent().appendingPathComponent("target")
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: target)
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o755])
            }
            #expect(throws: JournalFailure.unsafeStorage) {
                _ = try DurableRecoveryJournal(directory: directory)
            }
        }
    }

    @Test func alteredRecoveryIdentityIsNotAccepted() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(entry(), replacing: nil)
            let file = directory.appendingPathComponent("recovery.json")
            let contents = try String(contentsOf: file, encoding: .utf8)
            try contents.replacingOccurrences(of: "boot-a", with: "boot-b")
                .write(to: file, atomically: false, encoding: .utf8)
            #expect(throws: JournalFailure.corrupt) { try journal.load() }
            #expect(throws: JournalFailure.corrupt) {
                try journal.commit(entry(revision: 2), replacing: 1)
            }
        }
    }

    @Test(arguments: [UInt64(1), 3, UInt64.max])
    func replacementRequiresExactlyTheNextRevision(_ revision: UInt64) throws {
        try withDirectory { directory in
            let writer = try DurableRecoveryJournal(directory: directory)
            try writer.commit(entry(), replacing: nil)
            #expect(throws: JournalFailure.revisionConflict) {
                try writer.commit(entry(revision: revision, disposition: .unresolved), replacing: 1)
            }
            #expect(try writer.load() == entry())
        }
    }

    @Test func aSecondCreationCannotEraseExistingIntent() throws {
        try withDirectory { directory in
            let writer = try DurableRecoveryJournal(directory: directory)
            try writer.commit(entry(), replacing: nil)
            let competitor = try DurableRecoveryJournal(directory: directory)
            #expect(throws: JournalFailure.revisionConflict) {
                try competitor.commit(entry(revision: 2), replacing: nil)
            }
            #expect(try writer.load() == entry())
        }
    }

    @Test func recoveryIntentSurvivesReopening() throws {
        try withDirectory { directory in
            let writer = try DurableRecoveryJournal(directory: directory)
            try writer.commit(entry(), replacing: nil)
            let restarted = try DurableRecoveryJournal(directory: directory)
            #expect(try restarted.load() == entry())
        }
    }
}
