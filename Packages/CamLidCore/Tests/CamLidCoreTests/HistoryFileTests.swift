import Foundation
import Testing

@testable import CamLidCore

private func transition(revision: Int) throws -> StoredTransition {
    try StoredTransition(
        stateRevision: revision, category: .stateTransition,
        newState: .ready, reasonCodes: ["test"])
}

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("camlid-history-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    return dir
}

@Suite("File history storage (F12)")
struct HistoryFileTests {
    @Test("append and load round-trip across instances")
    func roundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = FileHistoryStorage(directory: dir)
        first.append(try transition(revision: 1))
        first.append(try transition(revision: 2))
        let second = FileHistoryStorage(directory: dir)
        let loaded = second.load()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.stateRevision) == [1, 2])
    }

    @Test("rotation bounds total bytes and retains newest")
    func rotationBounded() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileHistoryStorage(directory: dir, maxBytes: 4_096)
        for revision in 0..<200 {
            storage.append(try transition(revision: revision))
        }
        let loaded = storage.load()
        #expect(!loaded.isEmpty)
        #expect(loaded.last?.stateRevision == 199)
        let total = ["camlid-history.jsonl", "camlid-history.1.jsonl"].reduce(0) { sum, name in
            sum + ((try? FileManager.default.attributesOfItem(
                atPath: dir.appendingPathComponent(name).path)[.size] as? Int) ?? 0)
        }
        #expect(total <= 4_096)  // at most one record over the per-file cap
    }

    @Test("corrupt lines are skipped and counted")
    func corruptLines() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileHistoryStorage(directory: dir)
        storage.append(try transition(revision: 1))
        let url = dir.appendingPathComponent("camlid-history.jsonl")
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("not-json{{{\n".utf8))
            try? handle.close()
        }
        storage.append(try transition(revision: 2))
        #expect(storage.load().count == 2)
        #expect(storage.skippedCorruptLineCount() == 1)
        _ = storage.load()
        #expect(storage.skippedCorruptLineCount() == 1)
        #expect(storage.clear() == 2)
        #expect(storage.lastOperationError() == "historyCountUnknown")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("removeAll rewrites and reports counts")
    func removeRewrite() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileHistoryStorage(directory: dir)
        for revision in 0..<5 { storage.append(try transition(revision: revision)) }
        #expect(storage.removeAll { _ in false } == 0)
        #expect(storage.removeAll { $0.stateRevision < 3 } == 3)
        #expect(storage.load().map(\.stateRevision) == [3, 4])
        #expect(storage.removeAll { _ in true } == 2)
        #expect(storage.load().isEmpty)
    }

    @Test("removeAll refuses to parse or rewrite oversized history")
    func removeOversizedHistory() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("camlid-history.jsonl")
        let oversized = Data(repeating: 0x78, count: 4_096)
        try oversized.write(to: url)
        let storage = FileHistoryStorage(directory: dir, maxBytes: 1_024)

        #expect(storage.removeAll { _ in true } == 0)
        #expect(storage.lastOperationError() == "historyTooLarge")
        #expect(try Data(contentsOf: url) == oversized)
    }

    @Test("clear unlinks oversized regular history without claiming an exact count")
    func clearOversizedHistory() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("camlid-history.jsonl")
        let oversized = Data(repeating: 0x78, count: 4_096)
        try oversized.write(to: url)
        let storage = FileHistoryStorage(directory: dir, maxBytes: 1_024)

        #expect(storage.clear() == 0)
        #expect(storage.lastOperationError() == "historyCountUnknown")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("removeAll retains corrupt bytes and reports incomplete deletion")
    func removeAllCorruptData() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("camlid-history.jsonl")
        var data = try JSONEncoder().encode(transition(revision: 1))
        data.append(0x0A)
        data.append(contentsOf: Data("not-json{{{\n".utf8))
        try data.write(to: url)
        let storage = FileHistoryStorage(directory: dir)

        #expect(storage.removeAll { _ in true } == 1)
        #expect(storage.lastOperationError() == "historyCorruptLinesRetained")
        #expect(try String(contentsOf: url, encoding: .utf8) == "not-json{{{\n")
    }

    @Test("ActivityStore enforces retention over file storage")
    func storeRetention() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = Date(timeIntervalSince1970: 1_000_000)
        let storage = FileHistoryStorage(directory: dir)
        let store = ActivityStore(
            storage: storage, now: { Date(timeIntervalSince1970: 2_000_000) },
            retentionSeconds: 100, maxBytes: 20 * 1_024 * 1_024)
        let stale = try StoredTransition(
            timestamp: old, stateRevision: 0, category: .stateTransition,
            newState: .ready, reasonCodes: ["stale"])
        store.record(stale)
        #expect(store.transitions().isEmpty)
    }

    @Test("batched file records retain fresh entries and prune old ones")
    func batchRetention() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 2_000_000)
        let storage = FileHistoryStorage(directory: dir)
        let store = ActivityStore(storage: storage, now: { now }, retentionSeconds: 100)
        let stale = try StoredTransition(timestamp: now.addingTimeInterval(-101), stateRevision: 1,
            category: .stateTransition, newState: .ready, reasonCodes: ["stale"])
        let fresh = try StoredTransition(timestamp: now, stateRevision: 2,
            category: .stateTransition, newState: .ready, reasonCodes: ["fresh"])
        store.record([stale, fresh])
        #expect(storage.lastOperationError() == nil)
        #expect(store.transitions().map(\.id) == [fresh.id])
    }
}

@Suite("History failure regressions")
struct HistoryFailureTests {
    @Test func privatePermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-private-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileHistoryStorage(directory: dir)
        storage.append(try transition(revision: 1))
        #expect(storage.lastOperationError() == nil)
        let mode = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("camlid-history.jsonl").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
    @Test func invalidStorageIsObservable() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-invalid-\(UUID().uuidString)")
        try Data("file".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let storage = FileHistoryStorage(directory: path)
        storage.append(try transition(revision: 1))
        #expect(storage.lastOperationError() == "appendFailed")
        #expect(storage.removeAll { _ in true } == 0)
    }
    @Test func refusesSymlinkHistory() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("untouched")
        try Data("preserve".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("camlid-history.jsonl"), withDestinationURL: target)
        let storage = FileHistoryStorage(directory: dir)
        storage.append(try transition(revision: 1))
        #expect(storage.lastOperationError() != nil)
        #expect(try String(contentsOf: target, encoding: .utf8) == "preserve")
    }

    @Test func removeAndClearRefuseSymlinkHistory() throws {
        for action in ["removeAll", "clear"] {
            let dir = try tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let target = dir.appendingPathComponent("user-data")
            let history = dir.appendingPathComponent("camlid-history.jsonl")
            try Data("preserve-me".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: history, withDestinationURL: target)
            let storage = FileHistoryStorage(directory: dir)

            if action == "removeAll" {
                #expect(storage.removeAll { _ in true } == 0)
            } else {
                #expect(storage.clear() == 0)
            }
            #expect(storage.lastOperationError() == "unsafeHistoryFile")
            #expect(try String(contentsOf: target, encoding: .utf8) == "preserve-me")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: history.path) == target.path)
        }
    }
}
