import Foundation

/// Bounded runtime ingestion. Peer authentication lives in the transport;
/// receipt time is owned here, never trusted from a producer's payload.
public struct RuntimeAgentStore: Sendable {
    private var normalizer = EvidenceNormalizer()
    private var receipts: [String: Double] = [:]
    private var taskKeys: [String: String] = [:]
    private var waitDeadlines: [String: Double] = [:]
    private var waitRetentionSeconds: Double = 300
    public private(set) var lastRejection: String?

    public var trackedRunCount: Int { normalizer.trackedRunCount }
    public var retiredRunCount: Int { normalizer.retiredCount }

    public init() {}
    public mutating func configure(waitRetentionSeconds: Double) {
        self.waitRetentionSeconds = min(1_800, max(0, waitRetentionSeconds))
    }

    public mutating func ingest(_ data: Data, now: Double) throws -> String {
        _ = try BoundedPayload(data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw IPCError.invalidInput("invalidEvent") }
        let keys: Set<String> = ["provider", "sessionID", "runID", "parentRunID", "state", "evidenceKind", "confidence", "sequence", "epoch", "sourceTime", "receivedMonotonic"]
        guard Set(object.keys).isSubset(of: keys) else { throw IPCError.invalidInput("unexpectedEventFields") }
        let decoded = try JSONDecoder().decode(NormalizedEvent.self, from: data)
        guard ["orca", "claude", "codex", "opencode", "wrapper"].contains(decoded.provider) else { throw IPCError.invalidInput("unsupportedProvider") }
        let event = try NormalizedEvent(provider: decoded.provider, sessionID: decoded.sessionID, runID: decoded.runID,
            parentRunID: decoded.parentRunID, state: decoded.state, evidenceKind: decoded.evidenceKind,
            confidence: decoded.confidence, sequence: decoded.sequence, epoch: decoded.epoch,
            sourceTime: decoded.sourceTime, receivedMonotonic: now)
        let key = EvidenceNormalizer.runKey(provider: event.provider, sessionID: event.sessionID, runID: event.runID)
        let incomingTask = normalizer.task(
            provider: event.provider, sessionID: event.sessionID, runID: event.runID)
        let incomingProjected = tasks(now: now).first {
            $0.sessionID == event.sessionID && $0.runID == event.runID
                && self.provider(for: $0.id) == event.provider
        }
        let incomingWasNonHolding = incomingProjected.map {
            [.unknown, .waiting].contains($0.state) && !PolicyEngine.holdsSession($0, now: now)
        } ?? false
        retireExpiredTasks(now: now, excluding: key)
        let holdingCount = tasks(now: now).filter { PolicyEngine.holdsSession($0, now: now) }.count
        if incomingWasNonHolding, let incomingTask,
           incomingTask.state == .working, event.state == .unknown
        {
            _ = retireTask(incomingTask, now: now)
        }
        // Normalize transactionally. Existing idle identities and gap-fill
        // events can also add holding work; checking only new IDs misses them.
        var candidate = normalizer
        var outcome = candidate.normalize(event)
        if case .lateRejected(reason: "runTableFull") = outcome,
           normalizer.trackedRunCount >= normalizer.maxTrackedRuns,
           retireOneIdleTaskForTablePressure(now: now)
        {
            candidate = normalizer; outcome = candidate.normalize(event)
        }
        if case .epochReset(let epoch) = outcome, epoch == event.epoch { outcome = candidate.normalize(event) }
        if case .applied(let task) = outcome {
            let prospectiveHolds: Bool
            if task.state == .waiting {
                let deadline = waitDeadlines[task.id] ?? task.waitUntilMonotonic.map { $0 - 300 + waitRetentionSeconds }
                prospectiveHolds = deadline.map { now < $0 } ?? false
            } else { prospectiveHolds = PolicyEngine.holdsSession(task, now: now) }
            let previouslyHeld = incomingProjected.map { PolicyEngine.holdsSession($0, now: now) } ?? false
            if prospectiveHolds && holdingCount - (previouslyHeld ? 1 : 0) >= PolicyLimits.maxEnrolledTasks {
                lastRejection = "enrollmentFull"
                throw IPCError.policyDenied("enrollmentFull")
            }
        }
        normalizer = candidate
        if incomingWasNonHolding,
           case .duplicate = outcome,
           let incomingTask
        {
            _ = retireTask(incomingTask, now: now)
            outcome = .lateRejected(reason: "expiredReplay")
        } else if incomingWasNonHolding,
                  case .lateRejected = outcome,
                  let incomingTask
        {
            _ = retireTask(incomingTask, now: now)
        }
        pruneMetadata()
        switch outcome {
        case .applied(let task):
            if task.state == .waiting, waitDeadlines[task.id] == nil, let deadline = task.waitUntilMonotonic {
                waitDeadlines[task.id] = deadline - 300 + waitRetentionSeconds
            } else if task.state != .waiting { waitDeadlines.removeValue(forKey: task.id) }
            taskKeys[task.id] = key
            receipts[key] = now
            pruneMetadata()
            lastRejection = nil
            return "applied"
        case .buffered: return "buffered"
        case .duplicate: return "duplicate"
        case .lateRejected(let reason):
            lastRejection = reason
            throw IPCError.invalidInput(reason)
        case .reusedRunRejected(let reason):
            lastRejection = reason
            throw IPCError.invalidInput(reason)
        default: throw IPCError.invalidInput("eventRejected")
        }
    }

    public mutating func remove(provider: String) {
        let prefix = provider + "\0"
        normalizer.removeProvider(provider)
        receipts = receipts.filter { !$0.key.hasPrefix(prefix) }
        taskKeys = taskKeys.filter { !$0.value.hasPrefix(prefix) }
        waitDeadlines = waitDeadlines.filter { taskKeys[$0.key] != nil }
    }

    public func lastReceipt(provider: String) -> Double? {
        receipts.filter { $0.key.hasPrefix(provider + "\0") }.values.max()
    }

    /// Provider identity comes from the normalized tuple, including hashed IDs.
    public func provider(for taskID: String) -> String? {
        taskKeys[taskID]?.components(separatedBy: "\0").first
    }
    public func tasks(provider: String, now: Double) -> [AgentTask] {
        tasks(now: now).filter { self.provider(for: $0.id) == provider }
    }

    public func tasks(now: Double) -> [AgentTask] {
        normalizer.allTasks.map { task in
            if task.state == .waiting, let deadline = waitDeadlines[task.id] {
                return (try? AgentTask(id: task.id, sessionID: task.sessionID, runID: task.runID,
                    parentRunID: task.parentRunID, state: task.state, evidenceKind: task.evidenceKind,
                    confidence: task.confidence, waitUntilMonotonic: deadline)) ?? task
            }
            // A missing heartbeat cannot keep a working run active forever.
            let key = taskKeys[task.id] ?? ""
            guard task.state == .working, let receipt = receipts[key], now - receipt > 15 else { return task }
            return (try? AgentTask(id: task.id, sessionID: task.sessionID, runID: task.runID,
                parentRunID: task.parentRunID, state: .unknown, evidenceKind: task.evidenceKind,
                confidence: .unknown, unknownUntilMonotonic: receipt + 15 + 120)) ?? task
        }.sorted { $0.id < $1.id }
    }

    /// Retire only rows whose bounded evidence no longer holds protection.
    /// The normalizer retains each retired watermark to reject replay.
    private mutating func retireExpiredTasks(now: Double, excluding runKey: String) {
        for task in tasks(now: now) {
            guard taskKeys[task.id] != runKey else { continue }
            guard let provider = taskProvider(task) else { continue }
            guard [.working, .waiting, .unknown].contains(task.state),
                  !PolicyEngine.holdsSession(task, now: now),
                  normalizer.task(provider: provider, sessionID: task.sessionID, runID: task.runID) != nil
            else { continue }
            _ = retireTask(task, now: now)
        }
    }

    /// At hard table capacity, an idle row can be retired to admit a new run.
    /// Active or buffered identities remain untouched; the normalizer decides
    /// whether this retry has enough replay-history capacity to proceed.
    private mutating func retireOneIdleTaskForTablePressure(now: Double) -> Bool {
        let candidates = tasks(now: now)
            .filter { $0.state == .idle && !PolicyEngine.holdsSession($0, now: now) }
            .sorted {
                let lhs = receipts[taskKeys[$0.id] ?? ""] ?? .infinity
                let rhs = receipts[taskKeys[$1.id] ?? ""] ?? .infinity
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
        for task in candidates {
            guard let provider = taskProvider(task) else { continue }
            guard normalizer.task(provider: provider, sessionID: task.sessionID, runID: task.runID) != nil,
                  normalizer.retireInactiveRun(
                    provider: provider, sessionID: task.sessionID, runID: task.runID, now: now)
            else { continue }
            forgetMetadata(for: task)
            return true
        }
        return false
    }

    @discardableResult
    private mutating func retireTask(_ task: AgentTask, now: Double) -> Bool {
        guard let provider = taskProvider(task),
              normalizer.task(provider: provider, sessionID: task.sessionID, runID: task.runID) != nil,
              normalizer.retireInactiveRun(
                provider: provider, sessionID: task.sessionID, runID: task.runID, now: now)
        else { return false }
        forgetMetadata(for: task)
        return true
    }

    private func taskProvider(_ task: AgentTask) -> String? {
        taskKeys[task.id]?.components(separatedBy: "\0").first
    }

    private mutating func forgetMetadata(for task: AgentTask) {
        if let key = taskKeys.removeValue(forKey: task.id) {
            receipts.removeValue(forKey: key)
        }
        waitDeadlines.removeValue(forKey: task.id)
    }

    private mutating func pruneMetadata() {
        let present = Set(normalizer.allTasks.map(\.id))
        taskKeys = taskKeys.filter { present.contains($0.key) }
        waitDeadlines = waitDeadlines.filter { present.contains($0.key) }
        let liveKeys = Set(taskKeys.values)
        receipts = receipts.filter { liveKeys.contains($0.key) }
    }
}
