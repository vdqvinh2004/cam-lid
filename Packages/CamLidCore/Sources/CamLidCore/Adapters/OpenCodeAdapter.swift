/// Configured loopback/OpenCode plugin adapter (M3 T005).
///
/// Pure event/snapshot parsing and reconciliation. No subprocesses, no
/// network, no port scanning, no transcript storage: only whitelisted routing
/// fields are decoded; prompt, transcript, and file contents are never read.
///
/// Explicit opt-in via a configured loopback endpoint (fixed host/port) or a
/// local plugin. Without `optIn` (or without a configured endpoint) every
/// input is ignored.
///
/// State mapping: `busy` is active work (`working`); `retry` is an automatic
/// retry stall and maps to `waiting` (per the shared state model, waiting
/// covers input, permission, or retry); `idle` ends the turn after checking
/// tracked children. Permission requests map to `waiting`; denial maps to
/// `failed`; grants map back to `working`.
///
/// Snapshot reconciliation: a fresh status snapshot wins over the
/// event-stream view. Sessions present in the snapshot update the view;
/// missing sessions become bounded `unknown`, never invented completion.
/// Referenced children hold only through their previously tracked work state;
/// missing output cannot establish fresh work or inactivity. A stale snapshot emits bounded `unknown` for tracked runs and
/// requests a retry with bounded attempts (`maxReconcileAttempts`).
import Foundation

/// Whitelisted OpenCode event routing fields. Unknown keys are ignored.
public struct OpenCodeEventPayload: Sendable, Equatable, Decodable {
    public let type: String
    public let sessionID: String?
    public let runID: String?
    public let parentSessionID: String?
    public let permission: String?
    public let childSessionID: String?

    public init(
        type: String, sessionID: String? = nil, runID: String? = nil,
        parentSessionID: String? = nil, permission: String? = nil,
        childSessionID: String? = nil
    ) {
        self.type = type
        self.sessionID = sessionID
        self.runID = runID
        self.parentSessionID = parentSessionID
        self.permission = permission
        self.childSessionID = childSessionID
    }

    enum CodingKeys: String, CodingKey {
        case type, event, status, state, kind, name
        case sessionID, sessionId, session_id
        case runID, runId, run_id
        case parentSessionID, parentSessionId, parent_session_id, parentRunID, parent_run_id
        case permission, permissionAction, permission_action
        case childSessionID, childSessionId, child_session_id, childID, child_id
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        type = OpenCodeDecode.string(box, [.type, .event, .status, .state, .kind, .name]) ?? ""
        sessionID = OpenCodeDecode.string(box, [.sessionID, .sessionId, .session_id])
        runID = OpenCodeDecode.string(box, [.runID, .runId, .run_id])
        parentSessionID = OpenCodeDecode.string(box, [
            .parentSessionID, .parentSessionId, .parent_session_id,
            .parentRunID, .parent_run_id,
        ])
        permission = OpenCodeDecode.string(box, [
            .permission, .permissionAction, .permission_action,
        ])
        childSessionID = OpenCodeDecode.string(box, [
            .childSessionID, .childSessionId, .child_session_id, .childID, .child_id,
        ])
    }
}

/// One whitelisted OpenCode status-snapshot row. Unknown keys are ignored.
public struct OpenCodeSessionRow: Sendable, Equatable, Decodable {
    public let sessionID: String
    public let status: String
    public let parentSessionID: String?
    public let childSessionIDs: [String]
    public let sequence: Int?

    public init(
        sessionID: String, status: String, parentSessionID: String? = nil,
        childSessionIDs: [String] = [], sequence: Int? = nil
    ) {
        self.sessionID = sessionID
        self.status = status
        self.parentSessionID = parentSessionID
        self.childSessionIDs = childSessionIDs
        self.sequence = sequence
    }

    enum CodingKeys: String, CodingKey {
        case sessionID, sessionId, session_id, id
        case status, state, kind
        case parentSessionID, parentSessionId, parent_session_id
        case childSessionIDs, childSessions, child_sessions, children
        case sequence, seq
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        guard let session = OpenCodeDecode.string(box, [.sessionID, .sessionId, .session_id, .id])
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.sessionID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "missing session id"))
        }
        sessionID = session
        status = OpenCodeDecode.string(box, [.status, .state, .kind]) ?? "unknown"
        parentSessionID = OpenCodeDecode.string(box, [
            .parentSessionID, .parentSessionId, .parent_session_id,
        ])
        var children = OpenCodeDecode.stringArray(box, [
            .childSessionIDs, .childSessions, .child_sessions, .children,
        ])
        children.removeAll { $0.isEmpty }
        childSessionIDs = children
        sequence = OpenCodeDecode.int(box, [.sequence, .seq])
    }
}

enum OpenCodeDecode {
    static func string<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> String? {
        for key in keys {
            if let found: String = try? box.decode(String.self, forKey: key) { return found }
        }
        return nil
    }

    static func int<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> Int? {
        for key in keys {
            if let found: Int = try? box.decode(Int.self, forKey: key) { return found }
        }
        return nil
    }

    static func stringArray<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> [String] {
        for key in keys {
            if let found: [String] = try? box.decode([String].self, forKey: key) { return found }
        }
        return []
    }

    static func sessionRows<K: CodingKey>(
        _ box: KeyedDecodingContainer<K>, _ keys: [K]
    ) -> [OpenCodeSessionRow] {
        for key in keys {
            if let found: [OpenCodeSessionRow] = try? box.decode(
                [OpenCodeSessionRow].self, forKey: key)
            {
                return found
            }
        }
        return []
    }
}

public struct OpenCodeSnapshot: Sendable, Equatable, Decodable {
    public let sessions: [OpenCodeSessionRow]
    public init(sessions: [OpenCodeSessionRow]) { self.sessions = sessions }

    enum CodingKeys: String, CodingKey {
        case sessions, rows, tasks, data
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        sessions = OpenCodeDecode.sessionRows(box, [.sessions, .rows, .tasks, .data])
    }
}

public enum OpenCodeParseResult: Sendable, Equatable {
    case event(NormalizedEvent)
    case ignored(reason: String)
}

public struct OpenCodeReconcileResult: Sendable, Equatable {
    public let events: [NormalizedEvent]
    public let notes: [String]
}

public struct OpenCodeAdapter: Sendable {
    public static let providerID = "opencode"
    /// Bounded snapshot retry attempts before the caller must surface failure.
    public static let maxReconcileAttempts = 3
    public let optIn: Bool
    /// Configured loopback endpoint (fixed host/port) or plugin identity.
    /// Nil means unconfigured: every input is ignored, never port-scanned.
    public let endpoint: String?

    public static let maxRetainedIdentities = 64
    private var retainedSessions: Set<String> = []
    private var nextSequence: [String: Int] = [:]
    private var epochBySession: [String: Int] = [:]
    private var lastSnapshotState: [String: TaskState] = [:]
    // Provider snapshot counters are not normalized stream sequence numbers.
    private var snapshotSequence: [String: Int] = [:]
    private var childToParentSession: [String: String] = [:]
    private var attempts: Int = 0

    public init(optIn: Bool = false, endpoint: String? = nil) {
        self.optIn = optIn
        self.endpoint = endpoint
    }

    public var reconcileAttempts: Int { attempts }
    public var shouldRetrySnapshot: Bool { attempts < Self.maxReconcileAttempts }

    public mutating func recordSnapshotAttempt(success: Bool) {
        attempts = success ? 0 : min(attempts + 1, Self.maxReconcileAttempts)
    }

    public mutating func parse(json: Data, receivedMonotonic: Double) -> OpenCodeParseResult {
        guard let payload = try? JSONDecoder().decode(OpenCodeEventPayload.self, from: json) else {
            return .ignored(reason: gateReason() ?? "unparseable")
        }
        return parse(payload, receivedMonotonic: receivedMonotonic)
    }

    public mutating func parse(
        _ payload: OpenCodeEventPayload, receivedMonotonic: Double
    ) -> OpenCodeParseResult {
        if let reason = gateReason() { return .ignored(reason: reason) }
        let kind = fold(payload.type)
        let permission = fold(payload.permission ?? "")
        if permission == "grant" || permission == "allow" || permission == "approve" {
            return emit(state: .working, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if permission == "deny" || permission == "reject" {
            return emit(state: .failed, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("permission") || permission == "request" || permission == "ask" {
            return emit(state: .waiting, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("busy") {
            return emit(state: .working, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("stepstart") {
            return emit(state: .working, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        // A model step is not a session boundary. In installed --format json
        // streams step_finish with reason tool-calls is followed by more work.
        // Only session idle/terminal evidence can end the holding lifecycle.
        if kind.contains("stepfinish") {
            return .ignored(reason: "stepBoundaryNotSessionEnd")
        }
        if kind.contains("retry") {
            return emit(state: .waiting, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("idle") {
            return emit(state: .idle, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("childstart") || kind.contains("childcreated") {
            return emitChild(
                state: .working, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("childstop") || kind.contains("childdone")
            || kind.contains("childcomplete") || kind.contains("childfinish")
        {
            let failed = kind.contains("fail") || kind.contains("error")
            return emitChild(
                state: failed ? .failed : .completed, payload: payload,
                receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("complete") || kind.contains("done") || kind.contains("finish") {
            return emit(state: .completed, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        if kind.contains("fail") || kind.contains("error") {
            return emit(state: .failed, payload: payload, receivedMonotonic: receivedMonotonic)
        }
        return .ignored(reason: "unknownEvent")
    }

    /// Merges a fresh status snapshot over the event-stream view.
    ///
    /// F09: whole-snapshot, row-order independent reconciliation.
    /// - Whole snapshots are reconciled before parent aggregation (two-pass):
    ///   child links and proposed states are collected first, terminal child
    ///   links (completed/failed) retired, then idle parents are held only
    ///   for present active children.
    /// - Evidence loss uses bounded previously-working unknown (anchored by
    ///   `EvidenceNormalizer`, F06) instead of inventing idle/working.
    ///   Absence never proves completion. Missing children no longer stay
    ///   active unboundedly: they degrade to unknown once and expire via the
    ///   normalizer deadline.
    /// - `takenMonotonic`: when the snapshot was taken. Older than
    ///   `maxSnapshotAgeSeconds` counts as stale.
    public mutating func reconcile(
        snapshot: OpenCodeSnapshot,
        takenMonotonic: Double,
        receivedMonotonic: Double,
        nowMonotonic: Double,
        maxSnapshotAgeSeconds: Double = 15
    ) -> OpenCodeReconcileResult {
        if let reason = gateReason() {
            return OpenCodeReconcileResult(events: [], notes: [reason])
        }
        if nowMonotonic - takenMonotonic > maxSnapshotAgeSeconds {
            recordSnapshotAttempt(success: false)
            var events: [NormalizedEvent] = []
            var notes = ["snapshotStale"]
            if !shouldRetrySnapshot { notes.append("reconcileAttemptsExhausted") }
            for (session, _) in lastSnapshotState.sorted(by: { $0.key < $1.key }) {
                if case let .event(event) = nextEvent(
                    sessionID: session, runID: "main", parentRunID: nil,
                    state: .unknown, receivedMonotonic: receivedMonotonic)
                {
                    events.append(event)
                }
            }
            return OpenCodeReconcileResult(events: events, notes: notes)
        }
        recordSnapshotAttempt(success: true)
        // Pass 1: deterministic merge of rows (row-order independent).
        // Reject an invalid row before it can contribute a child link or a
        // parent aggregate. Filtering only at emission could invent working
        // evidence from a row whose own sequence/identity is unusable.
        let invalidRows = snapshot.sessions.filter { row in
            row.sessionID.isEmpty || row.sessionID.count > PolicyLimits.maxIDLength ||
            row.sessionID.rangeOfCharacter(from: .controlCharacters) != nil ||
            ([row.parentSessionID].compactMap { $0 } + row.childSessionIDs).contains { (try? validateID($0)) == nil } ||
            row.sequence.map { $0 < 0 || $0 == Int.max } == true
        }
        let invalidIDs = Set(invalidRows.map(\.sessionID))
        let validRows = snapshot.sessions.filter { !invalidIDs.contains($0.sessionID) }
        let rowByID = Self.mergedRows(validRows)
        let referencedIdentities = Set(rowByID.values.flatMap { [$0.sessionID] + [$0.parentSessionID].compactMap { $0 } + $0.childSessionIDs })
        let proposedRunKeys = Set(rowByID.keys.map { EvidenceNormalizer.runKey(provider: Self.providerID, sessionID: $0, runID: "main") })
        guard retainedSessions.union(referencedIdentities).count <= Self.maxRetainedIdentities,
              Set(nextSequence.keys).union(proposedRunKeys).count <= Self.maxRetainedIdentities else {
            return OpenCodeReconcileResult(events: [], notes: ["adapterCapacityFull"])
        }
        // Reject an inconsistent old snapshot before changing child links or
        // deriving parent state. Equal counters can still reflect child changes.
        if rowByID.values.contains(where: { row in
            guard let incoming = row.sequence, let previous = snapshotSequence[row.sessionID] else { return false }
            return incoming < previous
        }) {
            return OpenCodeReconcileResult(events: [], notes: ["snapshotSequenceRegressed"])
        }
        retainedSessions.formUnion(referencedIdentities)
        for row in rowByID.values {
            if let sequence = row.sequence { snapshotSequence[row.sessionID] = sequence }
        }
        // Children referenced by a parent row but without their own row are
        // confirmed present (rowless): they hold via tracked state and never
        // degrade while still referenced.
        var referenced: Set<String> = []
        for row in rowByID.values {
            for child in row.childSessionIDs {
                referenced.insert(child)
            }
        }
        // Record links from the whole snapshot before aggregation.
        // Sorted iteration keeps even conflicting claims deterministic.
        for (sessionID, row) in rowByID.sorted(by: { $0.key < $1.key }) {
            for child in row.childSessionIDs {
                childToParentSession[child] = sessionID
            }
            if let parent = row.parentSessionID {
                childToParentSession[sessionID] = parent
            }
        }
        var proposed: [String: TaskState] = [:]
        for (sessionID, row) in rowByID {
            proposed[sessionID] = Self.mapStatus(row.status)
        }
        // F09: retire terminal child links — completed/failed children stop
        // holding the parent.
        for child in Array(childToParentSession.keys) {
            if let state = proposed[child],
                state == .completed || state == .failed
            {
                childToParentSession.removeValue(forKey: child)
            }
        }
        // Pass 2: parent aggregation on final states, sorted for determinism.
        var finalStates: [String: TaskState] = [:]
        for sessionID in rowByID.keys.sorted() {
            let mapped = proposed[sessionID] ?? .unknown
            if mapped == .idle,
                hasActiveChildren(
                    ofParentSession: sessionID, presentStates: proposed,
                    referencedChildren: referenced)
            {
                finalStates[sessionID] = .working
            } else {
                finalStates[sessionID] = mapped
            }
        }
        var events: [NormalizedEvent] = []
        var notes: [String] = invalidRows.isEmpty ? [] : ["invalidSnapshotIdentityOrSequence"]
        for sessionID in rowByID.keys.sorted() {
            guard let row = rowByID[sessionID], let state = finalStates[sessionID] else { continue }
            if proposed[sessionID] == .idle, state == .working {
                notes.append("parentHeldForChildren:\(sessionID)")
            }
            if lastSnapshotState[sessionID] != state {
                if case let .event(event) = nextEvent(
                    sessionID: sessionID, runID: "main", parentRunID: row.parentSessionID,
                    state: state, receivedMonotonic: receivedMonotonic)
                {
                    events.append(event)
                    lastSnapshotState[sessionID] = state
                } else {
                    notes.append("invalidSnapshotIdentityOrSequence")
                }
            }
        }
        let seen = Set(rowByID.keys)
        for session in lastSnapshotState.keys.sorted() {
            if seen.contains(session) { continue }
            let previous = lastSnapshotState[session]
            let parentLink = childToParentSession[session]
            if parentLink != nil {
                // Tracked child confirmed by a parent row but without its own
                // row: still present, holds via tracked state, never degrades.
                if referenced.contains(session) {
                    notes.append("childHeldWithoutSnapshot:\(session)")
                    continue
                }
                // Tracked child missing from the snapshot: bounded
                // previously-working unknown, not indefinite activity.
                if previous == .working || previous == .waiting {
                    if case let .event(event) = nextEvent(
                        sessionID: session, runID: "main", parentRunID: parentLink,
                        state: .unknown, receivedMonotonic: receivedMonotonic)
                    {
                        events.append(event)
                        lastSnapshotState[session] = .unknown
                        notes.append("childMissingUnknown:\(session)")
                    } else {
                        notes.append("invalidSnapshotIdentityOrSequence")
                    }
                } else {
                    if previous == .completed || previous == .failed {
                        childToParentSession.removeValue(forKey: session)
                    }
                    notes.append("childHeldWithoutSnapshot:\(session)")
                }
                continue
            }
            // Disappeared parent/standalone: bounded unknown, never idle.
            // Absence must not prove completion or turn end.
            if previous == .working || previous == .waiting {
                if case let .event(event) = nextEvent(
                    sessionID: session, runID: "main", parentRunID: nil,
                    state: .unknown, receivedMonotonic: receivedMonotonic)
                {
                    events.append(event)
                    lastSnapshotState[session] = .unknown
                    notes.append("missingSessionUnknown:\(session)")
                } else {
                    notes.append("invalidSnapshotIdentityOrSequence")
                }
            }
        }
        return OpenCodeReconcileResult(events: events, notes: notes)
    }

    /// Records a stream reconnect: the next events for this session carry a
    /// fresh epoch and restart at sequence 0, so replays of old numbering
    /// report `epochReset`. Callers should reconcile with a fresh snapshot
    /// right after reconnecting.
    public mutating func noteReconnect(sessionID: String) {
        guard (try? validateID(sessionID)) != nil,
              retainedSessions.contains(sessionID) || retainedSessions.count < Self.maxRetainedIdentities,
              epochBySession[sessionKey(sessionID), default: 0] < Int.max - 1 else { return }
        retainedSessions.insert(sessionID)
        epochBySession[sessionKey(sessionID), default: 0] += 1
        let prefix = "\(Self.providerID)\0\(sessionID)\0"
        nextSequence = nextSequence.filter { !$0.key.hasPrefix(prefix) }
        snapshotSequence.removeValue(forKey: sessionID)
        lastSnapshotState.removeValue(forKey: sessionID)
    }

    public mutating func forgetSession(_ sessionID: String) {
        retainedSessions.remove(sessionID)
        nextSequence = nextSequence.filter { !$0.key.hasPrefix("\(Self.providerID)\0\(sessionID)\0") }
        epochBySession.removeValue(forKey: sessionKey(sessionID))
        lastSnapshotState.removeValue(forKey: sessionID)
        snapshotSequence.removeValue(forKey: sessionID)
        childToParentSession.removeValue(forKey: sessionID)
        childToParentSession = childToParentSession.filter { $0.value != sessionID }
    }

    public static func mapStatus(_ raw: String) -> TaskState {
        let folded = fold(raw)
        if folded.contains("busy") { return .working }
        if folded.contains("retry") { return .waiting }
        if folded.contains("idle") { return .idle }
        if folded.contains("complete") || folded.contains("done") || folded.contains("finish") {
            return .completed
        }
        if folded.contains("fail") || folded.contains("error") { return .failed }
        return .unknown
    }

    // MARK: - Private

    private static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func fold(_ text: String) -> String { Self.fold(text) }

    private func gateReason() -> String? {
        if !optIn { return "optInDisabled" }
        if (endpoint?.isEmpty ?? true) { return "noConfiguredEndpoint" }
        return nil
    }

    private func sessionKey(_ sessionID: String) -> String {
        "\(Self.providerID)\0\(sessionID)"
    }

    private func hasActiveChildren(
        ofParentSession parent: String, presentStates: [String: TaskState],
        referencedChildren: Set<String>
    ) -> Bool {
        // Present children with holding states keep an idle parent working.
        // Terminal (completed/failed) and idle children never hold. Rowless
        // children still referenced by the snapshot hold via tracked
        // working/waiting state; truly missing children never hold (bounded
        // via their own unknown).
        for (child, mappedParent) in childToParentSession {
            if mappedParent != parent { continue }
            if let state = presentStates[child] {
                if state == .working || state == .waiting || state == .unknown {
                    return true
                }
                continue
            }
            if referencedChildren.contains(child),
                let tracked = lastSnapshotState[child],
                tracked == .working || tracked == .waiting
            {
                return true
            }
        }
        return false
    }

    /// Deterministic merge of snapshot rows by sessionID (row-order
    /// independent). Duplicates merge children by union; status/sequence/
    /// parent resolve by max-sequence-wins with lexicographic tie-breaks.
    static func mergedRows(_ rows: [OpenCodeSessionRow]) -> [String: OpenCodeSessionRow] {
        var grouped: [String: [OpenCodeSessionRow]] = [:]
        for row in rows {
            grouped[row.sessionID, default: []].append(row)
        }
        var merged: [String: OpenCodeSessionRow] = [:]
        for (sessionID, group) in grouped {
            if group.count == 1 {
                merged[sessionID] = group[0]
                continue
            }
            var children = Set<String>()
            for row in group {
                for child in row.childSessionIDs where !child.isEmpty {
                    children.insert(child)
                }
            }
            let maxSeq: Int? = group.compactMap(\.sequence).max()
            let atMax = group.filter { ($0.sequence ?? -1) == (maxSeq ?? -1) }
            // Deterministic winner among max-sequence rows.
            let winner = atMax.sorted {
                if $0.status != $1.status { return $0.status < $1.status }
                return ($0.parentSessionID ?? "") < ($1.parentSessionID ?? "")
            }.first!
            // Deterministic parent: smallest non-nil across the group.
            let resolvedParent: String? = group.compactMap(\.parentSessionID).sorted().first
            merged[sessionID] = OpenCodeSessionRow(
                sessionID: sessionID,
                status: winner.status,
                parentSessionID: resolvedParent,
                childSessionIDs: children.sorted(),
                sequence: maxSeq)
        }
        return merged
    }

    private mutating func nextEvent(
        sessionID: String, runID: String, parentRunID: String?,
        state: TaskState, receivedMonotonic: Double
    ) -> OpenCodeParseResult {
        guard (try? validateID(sessionID)) != nil, (try? validateID(runID)) != nil,
              parentRunID.map({ (try? validateID($0)) != nil }) ?? true else { return .ignored(reason: "invalidIdentity") }
        let identities = Set([sessionID] + [parentRunID].compactMap { $0 })
        guard retainedSessions.union(identities).count <= Self.maxRetainedIdentities else { return .ignored(reason: "adapterCapacityFull") }
        let runKey = EvidenceNormalizer.runKey(
            provider: Self.providerID, sessionID: sessionID, runID: runID)
        guard nextSequence[runKey] != nil || nextSequence.count < Self.maxRetainedIdentities else { return .ignored(reason: "adapterCapacityFull") }
        let sequence = nextSequence[runKey, default: 0]
        guard sequence >= 0, sequence < Int.max else { return .ignored(reason: "counterExhausted") }
        let event = try? NormalizedEvent(
            provider: Self.providerID, sessionID: sessionID, runID: runID,
            parentRunID: parentRunID, state: state, evidenceKind: .lifecycle,
            confidence: .exact, sequence: sequence,
            epoch: epochBySession[sessionKey(sessionID), default: 0],
            receivedMonotonic: receivedMonotonic)
        guard let event else { return .ignored(reason: "invalidIdentity") }
        retainedSessions.formUnion(identities)
        nextSequence[runKey] = sequence + 1
        return .event(event)
    }

    private mutating func emit(
        state: TaskState, payload: OpenCodeEventPayload, receivedMonotonic: Double
    ) -> OpenCodeParseResult {
        guard let session = payload.sessionID, !session.isEmpty else {
            return .ignored(reason: "missingSessionID")
        }
        let run = (payload.runID?.isEmpty == false) ? payload.runID! : "main"
        let result = nextEvent(
            sessionID: session, runID: run, parentRunID: payload.parentSessionID,
            state: state, receivedMonotonic: receivedMonotonic)
        if case .event = result { lastSnapshotState[session] = state }
        return result
    }

    private mutating func emitChild(
        state: TaskState, payload: OpenCodeEventPayload, receivedMonotonic: Double
    ) -> OpenCodeParseResult {
        guard let session = payload.sessionID, !session.isEmpty else {
            return .ignored(reason: "missingSessionID")
        }
        guard let child = payload.childSessionID, !child.isEmpty else {
            return .ignored(reason: "missingChildSessionID")
        }
        let result = nextEvent(
            sessionID: child, runID: "main", parentRunID: session,
            state: state, receivedMonotonic: receivedMonotonic)
        if case .event = result {
            childToParentSession[child] = session
            lastSnapshotState[child] = state
        }
        return result
    }
}
