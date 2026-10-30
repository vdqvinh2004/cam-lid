/// Process discovery confidence and bounded fallback (M3 T006).
///
/// Pure matching/normalization over an injected process snapshot. All OS
/// interaction sits behind `ProcessListProvider`; tests use the in-memory
/// implementation. No live process inspection happens here.
///
/// Identity: PID plus process start time (`ProcessIdentity`). A bare PID is
/// never identity: PID reuse across launches yields distinct identities, and
/// a missing start time weakens the result to `unknown` confidence.
///
/// Confidence ladder: lifecycle (exact) outranks wrapper (inferred), which
/// outranks bare process presence (inferred at best, unknown when start time
/// is unavailable). Process-only discovery reports "process found, task
/// unknown": emitted evidence is always `unknown` state, `process` kind, and
/// can never claim semantic completion. It can never arm Auto (see
/// `canArmAuto` and the `processOnlyNoArm` rule in `PolicyEngine`).
///
/// Only executable basenames are matched and retained. Full command lines,
/// arguments, environment, and output text are never collected.
public struct ProcessIdentity: Sendable, Hashable, Equatable, Codable {
    public let pid: Int32
    /// Launch time, unix seconds. Nil when the provider cannot supply it.
    public let startTime: Double?

    public init(pid: Int32, startTime: Double?) throws(ValidationError) {
        guard pid > 0 else {
            throw ValidationError.outOfRange(field: "pid", value: Double(pid))
        }
        if let start = startTime {
            guard start.isFinite, start >= 0 else {
                throw ValidationError.outOfRange(field: "startTime", value: start)
            }
        }
        self.pid = pid
        self.startTime = startTime
    }
}

public struct ProcessRecord: Sendable, Equatable {
    public let identity: ProcessIdentity
    /// Executable basename only (for example "codex"). Never a full path
    /// with arguments.
    public let executableName: String
    public let parent: ProcessIdentity?
    public let lastSeenMonotonic: Double

    public init(
        identity: ProcessIdentity, executableName: String,
        parent: ProcessIdentity? = nil, lastSeenMonotonic: Double
    ) throws(ValidationError) {
        try validateString(executableName)
        guard lastSeenMonotonic.isFinite else {
            throw ValidationError.outOfRange(field: "lastSeenMonotonic", value: lastSeenMonotonic)
        }
        self.identity = identity
        self.executableName = executableName
        self.parent = parent
        self.lastSeenMonotonic = lastSeenMonotonic
    }
}

/// User-defined executable pattern or launch-wrapper attribution. Optional
/// fallback only: a match reports presence, never task state.
public struct CandidatePattern: Sendable, Equatable {
    public let executableContains: String
    public let provider: String
    public init(executableContains: String, provider: String) {
        self.executableContains = executableContains
        self.provider = provider
    }
}

public struct ProcessCandidate: Sendable, Equatable {
    public let identity: ProcessIdentity
    public let executableName: String
    public let provider: String
    public let confidence: Confidence
    public let parent: ProcessIdentity?
    public let reason: String
}

/// OS interaction seam. Production callers inject a snapshotter over live
/// process listing; tests inject `InMemoryProcessList`.
public protocol ProcessListProvider: Sendable {
    func snapshot() -> [ProcessRecord]
}

/// In-memory provider for tests and previews.
public struct InMemoryProcessList: ProcessListProvider {
    public var records: [ProcessRecord]
    public init(records: [ProcessRecord] = []) {
        self.records = records
    }
    public func snapshot() -> [ProcessRecord] {
        records
    }
}

public struct ProcessDiscovery: Sendable {
    public let provider: any ProcessListProvider
    public let patterns: [CandidatePattern]
    /// Bound on the fallback candidate list.
    public let maxFallbackEntries: Int

    public init(
        provider: any ProcessListProvider,
        patterns: [CandidatePattern] = [],
        maxFallbackEntries: Int = 10
    ) {
        self.provider = provider
        self.patterns = patterns
        self.maxFallbackEntries = maxFallbackEntries
    }

    /// Ladder rank for evidence precedence: lifecycle 3, wrapper 2, activity 1, process 0.
    public static func rank(kind: EvidenceKind) -> Int {
        switch kind {
        case .lifecycle: return 3
        case .wrapper: return 2
        case .activity: return 1
        case .process: return 0
        }
    }

    /// Confidence cap per evidence kind: lifecycle may be exact, wrapper and
    /// process cap at inferred (process drops to unknown without start time).
    public static func confidenceCap(for kind: EvidenceKind) -> Confidence {
        switch kind {
        case .lifecycle: return .exact
        case .wrapper, .activity, .process: return .inferred
        }
    }

    /// Auto-arm permission: process-only discovery never arms Auto.
    /// `PolicyEngine` enforces the same rule via `processOnlyNoArm`.
    public static func canArmAuto(kind: EvidenceKind) -> Bool {
        kind != .process
    }

    /// Bounded fallback candidates matching the configured patterns,
    /// deterministically ordered by (executable, pid, start time).
    public func discover() -> [ProcessCandidate] {
        var candidates: [ProcessCandidate] = []
        for record in provider.snapshot() {
            for pattern in patterns {
                guard !pattern.executableContains.isEmpty,
                    record.executableName.localizedCaseInsensitiveContains(pattern.executableContains)
                else { continue }
                let confidence: Confidence =
                    record.identity.startTime == nil ? .unknown : .inferred
                candidates.append(ProcessCandidate(
                    identity: record.identity,
                    executableName: record.executableName,
                    provider: pattern.provider,
                    confidence: confidence,
                    parent: record.parent,
                    reason: record.identity.startTime == nil
                        ? "processFoundStartTimeUnknown" : "processFoundTaskUnknown"))
                break
            }
        }
        candidates.sort {
            if $0.executableName != $1.executableName {
                return $0.executableName < $1.executableName
            }
            if $0.identity.pid != $1.identity.pid {
                return $0.identity.pid < $1.identity.pid
            }
            return ($0.identity.startTime ?? -1) < ($1.identity.startTime ?? -1)
        }
        return Array(candidates.prefix(max(0, maxFallbackEntries)))
    }

    /// Direct children of an identity within the current snapshot (process
    /// attribution only; never task state).
    public func children(of identity: ProcessIdentity) -> [ProcessRecord] {
        provider.snapshot().filter { $0.parent == identity }
    }

    /// Normalizes fallback candidates to `unknown`-state process evidence for
    /// one session scope. Never emits working/completed/failed: process
    /// presence cannot prove activity or completion.
    public func normalizedEvents(
        sessionID: String, receivedMonotonic: Double, sequenceBase: Int = 0
    ) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        var perRunCount: [String: Int] = [:]
        for candidate in discover() {
            let start = candidate.identity.startTime.map { String($0.bitPattern, radix: 16) } ?? "unknown"
            let runID = "pid-\(candidate.identity.pid)-start-\(start)"
            let runKey = "\(candidate.provider)\0\(runID)"
            let sequence = sequenceBase + perRunCount[runKey, default: 0]
            perRunCount[runKey, default: 0] += 1
            guard let event = try? NormalizedEvent(
                provider: candidate.provider, sessionID: sessionID, runID: runID,
                state: .unknown, evidenceKind: .process, confidence: candidate.confidence,
                sequence: sequence, receivedMonotonic: receivedMonotonic)
            else { continue }
            events.append(event)
        }
        return events
    }
}
