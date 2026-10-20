import CamLidCore
import Dispatch
import Foundation

private let historyDeadlineQueue = DispatchQueue(label: "camlid.history.deadlines", qos: .utility)

/// Serializes history I/O away from callers and bounds all accepted work,
/// including the operation currently running.
public final class AsyncHistoryRecorder: @unchecked Sendable {
    public static let maximumOutstandingOperations = 128

    private struct Job: @unchecked Sendable {
        let transition: StoredTransition?
        let isMutation: Bool
        let deadline: Double?
        let run: @Sendable () -> Void
        let expire: @Sendable () -> Void
    }

    private let store: ActivityStore
    private let diagnostic: (@Sendable () -> String?)?
    private let stateLock = NSLock()
    private var jobs: [Job] = []
    private var outstanding = 0
    private var workerScheduled = false
    private var cachedError: String?
    private var mutationsSealed = false
    private let worker = DispatchQueue(label: "camlid.history.recorder", qos: .utility)

    public init(
        store: ActivityStore,
        diagnostic: (@Sendable () -> String?)? = nil
    ) {
        self.store = store
        self.diagnostic = diagnostic
    }

    /// Most recently sampled storage diagnostic. Queue overflow reports
    /// `historyQueueFull` until a later completed operation samples storage.
    /// Reading this value never touches storage.
    public var lastError: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return cachedError
    }

    /// Enqueues without waiting. False means the bounded worker queue is full.
    @discardableResult
    public func record(_ transition: StoredTransition) -> Bool {
        enqueue(Job(transition: transition, isMutation: true, deadline: nil, run: {}, expire: {}))
    }

    /// Returns nil when the queue is full or the read misses its deadline.
    public func transitions(timeout: Double = 0.7) async -> [StoredTransition]? {
        await perform(timeout: timeout) { $0.transitions() }
    }

    /// Returns nil when the queue is full, encoding fails, or the deadline expires.
    public func exportRedactedJSON(salt: String, timeout: Double = 0.7) async -> Data? {
        await perform(timeout: timeout) { try? $0.exportRedactedJSON(salt: salt) }
    }

    /// Nil session ID deletes all history. Nil result means deletion was not
    /// confirmed before the deadline; a mutation already begun may still finish.
    public func delete(sessionID: String?, timeout: Double = 0.7) async -> DeletionReceipt? {
        await perform(timeout: timeout, isMutation: true) { store in
            if let sessionID { return store.delete(sessionID: sessionID) }
            return store.deleteAll()
        }
    }

    /// A barrier behind all previously accepted operations.
    public func flush(timeout: Double = 0.7) async -> Bool {
        await perform(timeout: timeout, requireHealthyStorage: false) { _ in true } ?? false
    }

    /// Linearizes mutation admission against the final quit barrier, including
    /// tasks scheduled before quit that reach this worker only afterward.
    func sealMutations() { stateLock.lock(); mutationsSealed = true; stateLock.unlock() }
    func resumeMutations() { stateLock.lock(); mutationsSealed = false; stateLock.unlock() }

    private func perform<Value: Sendable>(
        timeout: Double,
        isMutation: Bool = false,
        requireHealthyStorage: Bool = true,
        operation: @escaping @Sendable (ActivityStore) -> Value?
    ) async -> Value? {
        let deadline = Self.deadline(after: timeout)
        return await withCheckedContinuation { continuation in
            let reply = TimedHistoryReply(continuation: continuation, deadline: deadline)
            reply.armTimer()
            let accepted = enqueue(Job(transition: nil, isMutation: isMutation, deadline: deadline, run: { [weak self] in
                guard reply.begin() else { return }
                guard let self else { reply.resolve(nil); return }
                let result = operation(self.store)
                let error = self.sampleDiagnostic()
                reply.resolve(requireHealthyStorage && error != nil ? nil : result)
            }, expire: { reply.resolve(nil) }))
            if !accepted { reply.resolve(nil) }
        }
    }

    @discardableResult
    private func enqueue(_ job: Job) -> Bool {
        stateLock.lock()
        guard !mutationsSealed || !job.isMutation else { stateLock.unlock(); return false }
        guard outstanding < Self.maximumOutstandingOperations else {
            cachedError = "historyQueueFull"
            stateLock.unlock()
            return false
        }
        jobs.append(job)
        outstanding += 1
        let scheduleWorker = !workerScheduled
        workerScheduled = true
        stateLock.unlock()

        if scheduleWorker {
            // Keep this recorder alive until all accepted jobs have drained.
            worker.async { self.drain() }
        }
        return true
    }

    private func drain() {
        while true {
            stateLock.lock()
            guard !jobs.isEmpty else {
                workerScheduled = false
                stateLock.unlock()
                return
            }
            let job = jobs.removeFirst()
            var records: [StoredTransition] = []
            if let transition = job.transition {
                records.append(transition)
                // Reads, deletes and flush barriers keep their FIFO position.
                while let next = jobs.first?.transition {
                    records.append(next)
                    jobs.removeFirst()
                }
            }
            stateLock.unlock()

            if !records.isEmpty {
                store.record(records)
                sampleDiagnostic()
            } else if let deadline = job.deadline,
               ContinuousTime.now >= deadline {
                // In particular, a queued delete must not mutate storage after
                // its caller has already timed out.
                job.expire()
            } else {
                job.run()
            }

            stateLock.lock()
            outstanding -= max(1, records.count)
            stateLock.unlock()
        }
    }

    @discardableResult
    private func sampleDiagnostic() -> String? {
        let value = diagnostic?()
        stateLock.lock(); defer { stateLock.unlock() }
        cachedError = value
        return value
    }

    private static func deadline(after timeout: Double) -> Double {
        let now = ContinuousTime.now
        guard timeout.isFinite, timeout > 0 else { return now }
        return now + min(timeout, 3_600)
    }
}

private final class TimedHistoryReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let deadline: Double
    private var continuation: CheckedContinuation<Value?, Never>?
    private var timer: DispatchSourceTimer?

    init(continuation: CheckedContinuation<Value?, Never>, deadline: Double) {
        self.continuation = continuation
        self.deadline = deadline
    }

    func armTimer() {
        let timer = DispatchSource.makeTimerSource(queue: historyDeadlineQueue)
        timer.schedule(deadline: .now() + max(0, deadline - ContinuousTime.now))
        timer.setEventHandler { [weak self] in self?.resolve(nil) }
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            timer.cancel()
            return
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    /// Linearizes whether a queued operation began before its deadline.
    func begin() -> Bool {
        lock.lock()
        let mayBegin = continuation != nil && ContinuousTime.now < deadline
        lock.unlock()
        if !mayBegin { resolve(nil) }
        return mayBegin
    }

    func resolve(_ value: Value?) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        let result = ContinuousTime.now < deadline ? value : nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()

        timer?.cancel()
        continuation.resume(returning: result)
    }
}
