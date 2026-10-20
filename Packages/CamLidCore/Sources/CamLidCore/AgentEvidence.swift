/// Normalized agent evidence and run-identity normalization (M3 T001).
///
/// Pure value logic: no subprocesses, no network, no transcript storage.
/// Only state/confidence/counts are retained; prompt, code, terminal text,
/// command lines, and workspace contents are never decoded or stored.
///
/// Clocks: `receivedMonotonic` is a continuous monotonic clock that includes
/// time spent asleep. Wait/unknown deadlines derived from it therefore expire
/// across sleep exactly like elapsed wall time, matching `PolicyEngine`.
import Foundation
import CryptoKit

/// Single normalized lifecycle observation for one provider run.
///
/// Identity is (provider, sessionID, runID). `parentRunID` links child scope:
/// children inherit the parent's session and carry explicit run IDs.
/// `sequence` orders events within one `epoch`; `epoch` identifies a producer
/// generation (incremented on reconnect/restart) so replays of old numbering
/// never collide with fresh events.
public struct NormalizedEvent: Sendable, Equatable, Codable {
    public let provider: String
    public let sessionID: String
    public let runID: String
    public let parentRunID: String?
    public let state: TaskState
    public let evidenceKind: EvidenceKind
    public let confidence: Confidence
    public let sequence: Int
    public let epoch: Int
    /// Producer wall-clock seconds since epoch, when known. Optional.
    public let sourceTime: Double?
    /// Continuous monotonic receipt time, including time asleep.
    public let receivedMonotonic: Double

    private enum CodingKeys: String, CodingKey {
        case provider, sessionID, runID, parentRunID, state, evidenceKind,
             confidence, sequence, epoch, sourceTime, receivedMonotonic
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(provider: box.decode(String.self, forKey: .provider),
            sessionID: box.decode(String.self, forKey: .sessionID),
            runID: box.decode(String.self, forKey: .runID),
            parentRunID: box.decodeIfPresent(String.self, forKey: .parentRunID),
            state: box.decode(TaskState.self, forKey: .state),
            evidenceKind: box.decode(EvidenceKind.self, forKey: .evidenceKind),
            confidence: box.decode(Confidence.self, forKey: .confidence),
            sequence: box.decode(Int.self, forKey: .sequence),
            epoch: box.decodeIfPresent(Int.self, forKey: .epoch) ?? 0,
            sourceTime: box.decodeIfPresent(Double.self, forKey: .sourceTime),
            receivedMonotonic: box.decode(Double.self, forKey: .receivedMonotonic))
    }

    public init(
        provider: String,
        sessionID: String,
        runID: String,
        parentRunID: String? = nil,
        state: TaskState,
        evidenceKind: EvidenceKind,
        confidence: Confidence,
        sequence: Int,
        epoch: Int = 0,
        sourceTime: Double? = nil,
        receivedMonotonic: Double
    ) throws(ValidationError) {
        try validateID(provider)
        try validateID(sessionID)
        try validateID(runID)
        if let parent = parentRunID { try validateID(parent) }
        guard sequence >= 0, sequence < Int.max else {
            throw ValidationError.outOfRange(field: "sequence", value: Double(sequence))
        }
        guard epoch >= 0, epoch < Int.max else {
            throw ValidationError.outOfRange(field: "epoch", value: Double(epoch))
        }
        guard receivedMonotonic.isFinite else {
            throw ValidationError.outOfRange(field: "receivedMonotonic", value: receivedMonotonic)
        }
        if let source = sourceTime {
            guard source.isFinite else {
                throw ValidationError.outOfRange(field: "sourceTime", value: source)
            }
        }
        self.provider = provider
        self.sessionID = sessionID
        self.runID = runID
        self.parentRunID = parentRunID
        self.state = state
        self.evidenceKind = evidenceKind
        self.confidence = confidence
        self.sequence = sequence
        self.epoch = epoch
        self.sourceTime = sourceTime
        self.receivedMonotonic = receivedMonotonic
    }

    /// Elapsed continuous-monotonic time since receipt, including time asleep.
    public func elapsed(at nowMonotonic: Double) -> Double {
        nowMonotonic - receivedMonotonic
    }
}

/// Outcome of feeding one event through `EvidenceNormalizer`.
///
/// - `buffered` is an additional ordering outcome beyond the brief's five-case
///   list: an early (ahead-of-gap) event is held in the reorder buffer until
///   its predecessors arrive, then applied in sequence order.
public enum NormalizeOutcome: Sendable, Equatable {
    case applied(task: AgentTask)
    case duplicate
    case buffered
    case lateRejected(reason: String)
    case reusedRunRejected(reason: String)
    case epochReset(newEpoch: Int)
}

/// Run-identity, dedup, ordering, child-scope, and liveness normalization.
///
/// Rules:
/// - Dedup within a producer generation by (provider, session, run, sequence).
///   (The generation/epoch is part of the key so a reconnect replay of old
///   numbering never collides with fresh events.)
/// - Ordering by (epoch, sequence) with a bounded reorder buffer: ahead-of-gap
///   events are buffered; gap-fill applies buffered successors in order.
/// - A far-behind, never-seen sequence against established history (producer
///   restarted numbering without bumping the epoch) starts a new generation
///   and reports `epochReset`, as does any event from a newer epoch.
/// - Closed runs (completed/failed) keep a tombstone until the session ends:
///   stale sequences are `lateRejected`; reusing the same run ID for fresh
///   work is `reusedRunRejected` (callers must mint a new run ID).
/// - Liveness deadlines are `PolicyEngine.holdsSession`-compatible:
///   waiting holds through `receivedMonotonic + waitRetentionSeconds`,
///   unknown holds through `receivedMonotonic + unknownRetentionSeconds`.
///   Defaults follow FR-008: 5 minutes wait, 2 minutes unknown.
/// - Production retirement (T012): when the run table is exhausted, the
///   oldest *terminal* (tombstoned) run is evicted and a bounded tombstone
///   is remembered. Replays for a retired run are `retiredRun` rejections;
///   only a newer epoch reuses the ID as a fresh generation. Active runs
///   (working/waiting/unknown-holding) are never evicted: exhaustion with
///   no terminal run still reports `runTableFull`. The retired set is
///   bounded; exhaustion rejects additional retirement instead of forgetting
///   an identity and accepting a replay. Explicit session end/reset frees it.
public struct EvidenceNormalizer: Sendable {
    public let waitRetentionSeconds: Double
    public let unknownRetentionSeconds: Double
    public let maxReorderWindow: Int
    /// Bound on tracked run keys; exhaustion retires the oldest terminal
    /// run first (see retirement rules above). Enrollment itself is capped
    /// at 20 by `EnrollmentSet`.
    public let maxTrackedRuns: Int
    /// Bound on remembered retired tombstones. Exhaustion fails closed; a
    /// replay must never read as a fresh identity after forgetting history.
    public let maxRetiredTombstones: Int
    /// Bound on per-run dedup memory (F15). Only sequences within
    /// `(maxSeen - seenWindowSize ... maxSeen]` are retained; older
    /// sequences are rejected as `tooOld` even if unseen.
    public let seenWindowSize: Int

    private struct RunState: Sendable {
        var epoch: Int
        var nextExpected: Int
        var seen: Set<Int>
        var buffered: [Int: NormalizedEvent]
        var maxSeen: Int
        var tombstoneSequence: Int?
        var lastTask: AgentTask?
        // F06: anchored degradation. `hasWorked` remembers prior confirmed
        // working state; anchors pin the first transition into each degraded
        // state so repeats never extend the deadline. Cleared by fresh
        // working (and by idle/terminal, which end degradation).
        var hasWorked: Bool
        var firstUnknownAt: Double?
        var firstWaitingAt: Double?
        var lastActivityMonotonic: Double
    }

    /// Remembered terminal state for an evicted run (T012). Same-epoch
    /// events stay rejected; only a newer epoch starts a fresh generation.
    public struct RetiredTombstone: Sendable, Equatable {
        public var terminalSequence: Int
        public var epoch: Int
        public var lastState: TaskState
        public var retiredAtMonotonic: Double
    }

    private var runs: [String: RunState] = [:]
    private var childToParent: [String: String] = [:]
    private var retired: [String: RetiredTombstone] = [:]

    /// Number of remembered retired tombstones (observability for T012).
    public var retiredCount: Int { retired.count }
    public var trackedRunCount: Int { runs.count }

    public init(
        waitRetentionSeconds: Double = 300,
        unknownRetentionSeconds: Double = 120,
        maxReorderWindow: Int = 64,
        maxTrackedRuns: Int = 64,
        seenWindowSize: Int = 4096,
        maxRetiredTombstones: Int = 256
    ) {
        self.waitRetentionSeconds = waitRetentionSeconds
        self.unknownRetentionSeconds = unknownRetentionSeconds
        self.maxReorderWindow = min(64, max(1, maxReorderWindow))
        self.maxTrackedRuns = min(64, max(1, maxTrackedRuns))
        self.seenWindowSize = min(4096, max(1, seenWindowSize))
        self.maxRetiredTombstones = min(4096, max(1, maxRetiredTombstones))
    }

    public static func runKey(provider: String, sessionID: String, runID: String) -> String {
        "\(provider)\0\(sessionID)\0\(runID)"
    }

    private static func sessionPrefix(provider: String, sessionID: String) -> String {
        "\(provider)\0\(sessionID)\0"
    }

    public mutating func normalize(_ event: NormalizedEvent) -> NormalizeOutcome {
        let key = Self.runKey(
            provider: event.provider, sessionID: event.sessionID, runID: event.runID)
        if let parent = event.parentRunID, parent == event.runID {
            return .lateRejected(reason: "selfParent")
        }
        var initialExpected = 0
        if runs[key] == nil {
            if let tomb = retired[key] {
                let inactive = ![TaskState.completed, .failed].contains(tomb.lastState)
                let freshContinuation = inactive && event.epoch == tomb.epoch && event.sequence > tomb.terminalSequence
                    && [TaskState.working, .idle, .completed, .failed].contains(event.state)
                guard event.epoch > tomb.epoch || freshContinuation else {
                    return .lateRejected(reason: "retiredRun")
                }
                if freshContinuation { initialExpected = event.sequence }
            }
            if runs.count >= maxTrackedRuns {
                if !retireOldestTerminal(now: event.receivedMonotonic) {
                    return .lateRejected(reason: retired.count >= maxRetiredTombstones ? "retirementHistoryFull" : "runTableFull")
                }
            }
            retired.removeValue(forKey: key)
        }
        var current = runs[key] ?? RunState(
            epoch: event.epoch, nextExpected: initialExpected, seen: [],
            buffered: [:], maxSeen: -1, tombstoneSequence: nil, lastTask: nil,
            hasWorked: false, firstUnknownAt: nil, firstWaitingAt: nil,
            lastActivityMonotonic: event.receivedMonotonic)
        current.lastActivityMonotonic = event.receivedMonotonic

        if event.epoch > current.epoch {
            runs[key] = RunState(
                epoch: event.epoch, nextExpected: 0, seen: [],
                buffered: [:], maxSeen: -1, tombstoneSequence: nil, lastTask: nil,
                hasWorked: false, firstUnknownAt: nil, firstWaitingAt: nil,
                lastActivityMonotonic: event.receivedMonotonic)
            recordChildLink(event: event, key: key)
            return .epochReset(newEpoch: event.epoch)
        }
        if event.epoch < current.epoch {
            return .lateRejected(reason: "staleEpoch")
        }
        // F15: ancient sequences outside the dedup window are too old even
        // if unseen (evicted). Precedence over far-behind epochReset so
        // evicted replays never start a new generation.
        if event.sequence <= current.maxSeen - seenWindowSize {
            return .lateRejected(reason: "tooOld")
        }
        if !current.seen.contains(event.sequence),
            event.sequence < current.nextExpected - maxReorderWindow,
            current.maxSeen > maxReorderWindow
        {
            guard current.epoch < Int.max - 1 else {
                return .lateRejected(reason: "epochExhausted")
            }
            let fresh = current.epoch + 1
            runs[key] = RunState(
                epoch: fresh, nextExpected: 0, seen: [],
                buffered: [:], maxSeen: -1, tombstoneSequence: nil, lastTask: nil,
                hasWorked: false, firstUnknownAt: nil, firstWaitingAt: nil,
                lastActivityMonotonic: event.receivedMonotonic)
            recordChildLink(event: event, key: key)
            return .epochReset(newEpoch: fresh)
        }
        // Terminal runs report the tombstone first: replays after close
        // are closed-run rejections, never duplicate reopenings.
        if let tomb = current.tombstoneSequence {
            if event.sequence <= tomb {
                return .lateRejected(reason: "closedRun")
            }
            return .reusedRunRejected(reason: "runIDReuseRequiresNewRunID")
        }
        if current.seen.contains(event.sequence) || current.buffered[event.sequence] != nil {
            return .duplicate
        }
        if event.sequence == current.nextExpected {
            boundedInsert(event.sequence, into: &current)
            current.nextExpected += 1
            current.lastTask = makeAnchoredTask(for: event, state: &current)
            if event.state == .completed || event.state == .failed {
                current.tombstoneSequence = event.sequence
                // F07: stop drain at terminal — discard (do not apply) all
                // further buffered events for this run identity.
                current.buffered.removeAll()
            } else {
                while let queued = current.buffered[current.nextExpected] {
                    current.buffered.removeValue(forKey: current.nextExpected)
                    // Already in `seen` from buffer time; maxSeen unchanged.
                    current.nextExpected += 1
                    current.lastTask = makeAnchoredTask(for: queued, state: &current)
                    if queued.state == .completed || queued.state == .failed {
                        current.tombstoneSequence = queued.sequence
                        current.buffered.removeAll()
                        break
                    }
                }
            }
            // F15: drop any buffered entries that fell below the window.
            evictBelowWindow(into: &current)
            runs[key] = current
            recordChildLink(event: event, key: key)
            guard let final = current.lastTask else {
                return .lateRejected(reason: "invalidIdentity")
            }
            return .applied(task: final)
        }
        if event.sequence > current.nextExpected {
            guard current.buffered.count < maxReorderWindow else {
                return .lateRejected(reason: "reorderBufferFull")
            }
            current.buffered[event.sequence] = event
            boundedInsert(event.sequence, into: &current)
            runs[key] = current
            recordChildLink(event: event, key: key)
            return .buffered
        }
        return .lateRejected(reason: "staleSequence")
    }

    /// Batch entry: sorts by (provider, session, run, epoch, sequence) so
    /// reordered deliveries apply in order, then feeds events one by one.
    public mutating func normalizeBatch(_ events: [NormalizedEvent]) -> [NormalizeOutcome] {
        events
            .sorted {
                if $0.provider != $1.provider { return $0.provider < $1.provider }
                if $0.sessionID != $1.sessionID { return $0.sessionID < $1.sessionID }
                if $0.runID != $1.runID { return $0.runID < $1.runID }
                if $0.epoch != $1.epoch { return $0.epoch < $1.epoch }
                return $0.sequence < $1.sequence
            }
            .map { normalize($0) }
    }

    /// Latest applied task for a run, if any event applied yet.
    public func task(provider: String, sessionID: String, runID: String) -> AgentTask? {
        runs[Self.runKey(provider: provider, sessionID: sessionID, runID: runID)]?.lastTask
    }

    /// All latest applied tasks across tracked runs.
    public var allTasks: [AgentTask] {
        runs.values.compactMap(\.lastTask)
    }

    /// Latest applied tasks for one session (parent and children share it).
    public func tasksInSession(provider: String, sessionID: String) -> [AgentTask] {
        let prefix = Self.sessionPrefix(provider: provider, sessionID: sessionID)
        return runs.filter { $0.key.hasPrefix(prefix) }.values.compactMap(\.lastTask)
    }

    /// Explicit parent link for a child run, if recorded.
    public func parentRunID(provider: String, sessionID: String, childRunID: String) -> String? {
        childToParent[Self.runKey(provider: provider, sessionID: sessionID, runID: childRunID)]
    }

    /// Child run IDs recorded under a parent run.
    public func childRunIDs(provider: String, sessionID: String, parentRunID: String) -> [String] {
        let prefix = Self.sessionPrefix(provider: provider, sessionID: sessionID)
        return childToParent.compactMap { (childKey, parent) -> String? in
            guard parent == parentRunID, childKey.hasPrefix(prefix) else { return nil }
            let parts = childKey.split(separator: "\0", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            return String(parts[2])
        }.sorted()
    }

    /// Ends a session: clears runs, tombstones, retired tombstones and child
    /// links so the same run IDs may be reused by a later session generation.
    public mutating func endSession(provider: String, sessionID: String) {
        let prefix = Self.sessionPrefix(provider: provider, sessionID: sessionID)
        runs = runs.filter { !$0.key.hasPrefix(prefix) }
        childToParent = childToParent.filter { !$0.key.hasPrefix(prefix) }
        retired = retired.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Explicit source removal includes rows that never applied a task because
    /// all their events were buffered. Visible-task indexes are insufficient.
    public mutating func removeProvider(_ provider: String) {
        let prefix = provider + "\0"
        runs = runs.filter { !$0.key.hasPrefix(prefix) }
        childToParent = childToParent.filter { !$0.key.hasPrefix(prefix) }
        retired = retired.filter { !$0.key.hasPrefix(prefix) }
    }

    /// The runtime owns receipt freshness and decides which rows no longer
    /// hold. Retain their sequence watermark; only new working evidence or a
    /// newer generation may reactivate a nonterminal inactive identity. New
    /// terminal/idle evidence may close it without creating a holding deadline.
    @discardableResult public mutating func retireInactiveRun(provider: String, sessionID: String, runID: String, now: Double) -> Bool {
        let key = Self.runKey(provider: provider, sessionID: sessionID, runID: runID)
        guard let state = runs[key], let task = state.lastTask, state.buffered.isEmpty,
              ![TaskState.completed, .failed].contains(task.state) else { return false }
        return retire(key: key, state: state, sequence: state.maxSeen,
            lastState: task.state == .working ? .unknown : task.state, now: now)
    }

    public mutating func reset() {
        runs = [:]
        childToParent = [:]
        retired = [:]
    }

    /// Evicts the least-recently-active terminal run, remembering a bounded
    /// tombstone. Returns false when every tracked run is still active, in
    /// which case exhaustion stays a rejection instead of an eviction.
    private mutating func retireOldestTerminal(now: Double) -> Bool {
        let victim = runs
            .filter { $0.value.tombstoneSequence != nil }
            .min { $0.value.lastActivityMonotonic < $1.value.lastActivityMonotonic }
        guard let (key, state) = victim,
            let terminal = state.tombstoneSequence,
            let lastState = state.lastTask?.state
        else { return false }
        return retire(key: key, state: state, sequence: terminal, lastState: lastState, now: now)
    }

    private mutating func retire(key: String, state: RunState, sequence: Int, lastState: TaskState, now: Double) -> Bool {
        guard retired[key] != nil || retired.count < maxRetiredTombstones else { return false }
        runs.removeValue(forKey: key)
        childToParent.removeValue(forKey: key)
        let parts = key.split(separator: "\0", omittingEmptySubsequences: false)
        if parts.count == 3 {
            let runID = String(parts[2])
            let prefix = Self.sessionPrefix(provider: String(parts[0]), sessionID: String(parts[1]))
            childToParent = childToParent.filter { !($0.key.hasPrefix(prefix) && $0.value == runID) }
        }
        retired[key] = RetiredTombstone(
            terminalSequence: sequence, epoch: state.epoch,
            lastState: lastState, retiredAtMonotonic: now)
        return true
    }

    // MARK: - Private

    private mutating func recordChildLink(event: NormalizedEvent, key: String) {
        if let parent = event.parentRunID {
            childToParent[key] = parent
        }
    }

    /// F15: bounded dedup insert. Tracks maxSeen and evicts sequences at or
    /// below `maxSeen - seenWindowSize`, keeping memory bounded.
    private mutating func boundedInsert(_ sequence: Int, into state: inout RunState) {
        state.seen.insert(sequence)
        if sequence > state.maxSeen {
            state.maxSeen = sequence
        }
        if state.seen.count > seenWindowSize {
            let cutoff = state.maxSeen - seenWindowSize
            state.seen = Set(state.seen.filter { $0 > cutoff })
        }
    }

    /// F15: discard buffered entries that fell below the window.
    private func evictBelowWindow(into state: inout RunState) {
        let cutoff = state.maxSeen - seenWindowSize
        // Only filter when there is something plausibly below the window.
        if !state.buffered.isEmpty {
            state.buffered = state.buffered.filter { $0.key > cutoff }
        }
    }

    /// F06: anchored deadlines. The first transition into unknown/waiting
    /// pins the deadline; later snapshots never extend it. A run that never
    /// reached working gets no holding deadline from unknown. Fresh working
    /// clears degradation; idle/terminal also end degradation.
    private func makeAnchoredTask(for event: NormalizedEvent, state: inout RunState) -> AgentTask? {
        let rawID = "\(event.provider)/\(event.sessionID)/\(event.runID)"
        let ambiguous = [event.provider, event.sessionID, event.runID].contains { $0.contains("/") }
        let id = !ambiguous && rawID.count <= PolicyLimits.maxIDLength ? rawID : "evt-\(stableHashHex(Self.runKey(provider: event.provider, sessionID: event.sessionID, runID: event.runID)))"
        let waitUntil: Double?
        let unknownUntil: Double?
        switch event.state {
        case .working:
            state.hasWorked = true
            state.firstUnknownAt = nil
            state.firstWaitingAt = nil
            waitUntil = nil
            unknownUntil = nil
        case .waiting:
            if state.firstWaitingAt == nil {
                state.firstWaitingAt = event.receivedMonotonic
            }
            let anchor = state.firstWaitingAt ?? event.receivedMonotonic
            waitUntil = anchor + waitRetentionSeconds
            unknownUntil = nil
        case .unknown:
            if !state.hasWorked {
                waitUntil = nil
                unknownUntil = nil
            } else {
                if state.firstUnknownAt == nil {
                    state.firstUnknownAt = event.receivedMonotonic
                }
                let anchor = state.firstUnknownAt ?? event.receivedMonotonic
                unknownUntil = anchor + unknownRetentionSeconds
                waitUntil = nil
            }
        case .idle, .completed, .failed:
            state.hasWorked = false
            state.firstUnknownAt = nil
            state.firstWaitingAt = nil
            waitUntil = nil
            unknownUntil = nil
        }
        return try? AgentTask(
            id: id, sessionID: event.sessionID, runID: event.runID,
            parentRunID: event.parentRunID, state: event.state,
            evidenceKind: event.evidenceKind, confidence: event.confidence,
            waitUntilMonotonic: waitUntil, unknownUntilMonotonic: unknownUntil
        )
    }

    /// F15: test hook — bounded dedup size for one run.
    public func seenCount(provider: String, sessionID: String, runID: String) -> Int? {
        runs[Self.runKey(provider: provider, sessionID: sessionID, runID: runID)]?.seen.count
    }

    /// F15: test hook — highest sequence observed for one run.
    public func maxSeenSequence(provider: String, sessionID: String, runID: String) -> Int? {
        runs[Self.runKey(provider: provider, sessionID: sessionID, runID: runID)]?.maxSeen
    }
}

private func stableHashHex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}
