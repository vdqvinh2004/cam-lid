import Dispatch
import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("Asynchronous history recorder", .serialized)
struct AsyncHistoryRecorderTests {
    @Test("record returns while storage blocks and timed reads return nil")
    func callerNeverWaitsForHistoryStorage() async throws {
        let storage = BlockingHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage, now: { historyTestNow }))
        let started = DispatchTime.now().uptimeNanoseconds
        #expect(recorder.record(try transition(revision: 1)))
        #expect(elapsed(since: started) < 0.05)
        #expect(storage.waitForFirstAppend(timeout: 1))

        let readStarted = DispatchTime.now().uptimeNanoseconds
        let snapshot = await recorder.transitions(timeout: 0.05)
        #expect(snapshot == nil)
        #expect(elapsed(since: readStarted) < 0.5)

        let errorReadStarted = DispatchTime.now().uptimeNanoseconds
        #expect(recorder.lastError == nil)
        #expect(elapsed(since: errorReadStarted) < 0.05)

        storage.releaseFirstAppend.signal()
        #expect(await recorder.flush(timeout: 1))
    }

    @Test("a read that completes after its deadline cannot publish late data")
    func lateReadResultIsIgnored() async throws {
        let storage = BlockingLoadHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage, now: { historyTestNow }))
        let read = Task { await recorder.transitions(timeout: 0.05) }
        #expect(storage.waitForFirstLoad(timeout: 1))
        #expect(await read.value == nil)

        storage.releaseFirstLoad.signal()
        #expect(await recorder.flush(timeout: 1))
        #expect(await recorder.transitions(timeout: 1) == [])
    }

    @Test("the 128-operation bound counts active and pending work")
    func queueCapacityIncludesActiveOperation() async throws {
        let storage = BlockingHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage, now: { historyTestNow }))
        #expect(recorder.record(try transition(revision: 1)))
        #expect(storage.waitForFirstAppend(timeout: 1))

        for revision in 2...AsyncHistoryRecorder.maximumOutstandingOperations {
            #expect(recorder.record(try transition(revision: revision)))
        }
        #expect(!recorder.record(try transition(revision: 129)))
        #expect(recorder.lastError == "historyQueueFull")

        storage.releaseFirstAppend.signal()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorder.flush(timeout: 1))
        #expect(storage.appendedCount == AsyncHistoryRecorder.maximumOutstandingOperations)
        #expect(recorder.lastError == nil)
    }

    @Test("flush orders records and reads; exports redact; deletes report receipts")
    func orderedHistoryOperations() async throws {
        let storage = InMemoryHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage, now: { historyTestNow }))
        let records = try (1...3).map(transition(revision:))
        for record in records { #expect(recorder.record(record)) }
        #expect(await recorder.flush(timeout: 1))

        let snapshot = await recorder.transitions(timeout: 1)
        #expect(snapshot?.map(\.id) == records.map(\.id))
        let exported = await recorder.exportRedactedJSON(salt: "test-salt", timeout: 1)
        #expect(exported != nil)
        #expect(!(String(data: exported ?? Data(), encoding: .utf8) ?? "").contains("session-2"))

        let oneReceipt = await recorder.delete(sessionID: "session-2", timeout: 1)
        #expect(oneReceipt?.scope == .session)
        #expect(oneReceipt?.removedCount == 1)
        #expect(await recorder.transitions(timeout: 1)?.count == 2)

        let allReceipt = await recorder.delete(sessionID: nil, timeout: 1)
        #expect(allReceipt?.scope == .all)
        #expect(allReceipt?.removedCount == 2)
        #expect(await recorder.transitions(timeout: 1)?.isEmpty == true)
    }

    @Test("a queued record burst amortizes retention scans without losing records")
    func queuedBurstAmortizesRetention() async throws {
        let storage = BlockingHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage, now: { historyTestNow }))
        #expect(recorder.record(try transition(revision: 1)))
        #expect(storage.waitForFirstAppend(timeout: 1))
        for revision in 2...33 { #expect(recorder.record(try transition(revision: revision))) }
        #expect(await recorder.delete(sessionID: "session-1", timeout: 0.05) == nil)
        for revision in 34...65 { #expect(recorder.record(try transition(revision: revision))) }
        storage.releaseFirstAppend.signal()
        #expect(await recorder.flush(timeout: 2))
        #expect(storage.appendedCount == 65)
        #expect(storage.loadCallCount == 3)
        #expect(storage.deleteCallCount == 0)
    }

    @Test("expired queued deletion never starts storage mutation")
    func timedOutQueuedDeleteIsSkipped() async throws {
        let storage = BlockingHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage))
        #expect(recorder.record(try transition(revision: 1)))
        #expect(storage.waitForFirstAppend(timeout: 1))

        let started = DispatchTime.now().uptimeNanoseconds
        let receipt = await recorder.delete(sessionID: "session-1", timeout: 0.05)
        #expect(receipt == nil)
        #expect(elapsed(since: started) < 0.5)

        storage.releaseFirstAppend.signal()
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorder.flush(timeout: 1))
        #expect(storage.deleteCallCount == 0)
    }

    @Test("diagnostic is sampled on worker and cached for lock-only reads")
    func storageErrorDiagnosticIsCached() async throws {
        let probe = DiagnosticProbe("diskUnavailable")
        let recorder = AsyncHistoryRecorder(
            store: ActivityStore(storage: InMemoryHistoryStorage(), now: { historyTestNow }),
            diagnostic: { probe.read() }
        )
        #expect(recorder.record(try transition(revision: 1)))
        #expect(await recorder.flush(timeout: 1))
        #expect(recorder.lastError == "diskUnavailable")
        #expect(probe.readCount >= 2)
        #expect(await recorder.transitions(timeout: 1) == nil)
        #expect(await recorder.delete(sessionID: nil, timeout: 1) == nil)

        probe.set(nil)
        #expect(await recorder.flush(timeout: 1))
        #expect(recorder.lastError == nil)
    }
}

private func transition(revision: Int) throws -> StoredTransition {
    try StoredTransition(
        sessionID: "session-\(revision)", timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(revision)),
        stateRevision: revision, category: .stateTransition, previousState: .ready,
        newState: .protected, reasonCodes: ["armed"], providerKind: "codex"
    )
}

private let historyTestNow = Date(timeIntervalSince1970: 1_700_000_010)

private func elapsed(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
}

private final class BlockingHistoryStorage: HistoryStorage, @unchecked Sendable {
    let firstAppendEntered = DispatchSemaphore(value: 0)
    let releaseFirstAppend = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var shouldBlockFirstAppend = true
    private var appendCount = 0
    private var deleteCount = 0
    private var loadCount = 0

    var loadCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return loadCount
    }

    func waitForFirstAppend(timeout: TimeInterval) -> Bool {
        firstAppendEntered.wait(timeout: .now() + timeout) == .success
    }

    var appendedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return appendCount
    }

    var deleteCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return deleteCount
    }

    func append(_ record: StoredTransition) {
        lock.lock()
        let shouldBlock = shouldBlockFirstAppend
        shouldBlockFirstAppend = false
        lock.unlock()
        if shouldBlock {
            firstAppendEntered.signal()
            releaseFirstAppend.wait()
        }
        lock.lock(); appendCount += 1; lock.unlock()
    }

    func load() -> [StoredTransition] {
        lock.lock(); loadCount += 1; lock.unlock()
        return []
    }

    func removeAll(where shouldRemove: @Sendable (StoredTransition) -> Bool) -> Int {
        lock.lock(); deleteCount += 1; lock.unlock()
        return 0
    }

    func clear() -> Int {
        lock.lock(); deleteCount += 1; lock.unlock()
        return 0
    }
}

private final class BlockingLoadHistoryStorage: HistoryStorage, @unchecked Sendable {
    let firstLoadEntered = DispatchSemaphore(value: 0)
    let releaseFirstLoad = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var shouldBlockFirstLoad = true

    func waitForFirstLoad(timeout: TimeInterval) -> Bool {
        firstLoadEntered.wait(timeout: .now() + timeout) == .success
    }

    func append(_ record: StoredTransition) {}

    func load() -> [StoredTransition] {
        lock.lock()
        let shouldBlock = shouldBlockFirstLoad
        shouldBlockFirstLoad = false
        lock.unlock()
        if shouldBlock {
            firstLoadEntered.signal()
            releaseFirstLoad.wait()
        }
        return []
    }

    func removeAll(where shouldRemove: @Sendable (StoredTransition) -> Bool) -> Int { 0 }

    func clear() -> Int { 0 }
}

private final class DiagnosticProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var reads = 0

    init(_ value: String?) { self.value = value }

    var readCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    func read() -> String? {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        return value
    }

    func set(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        self.value = value
    }
}
