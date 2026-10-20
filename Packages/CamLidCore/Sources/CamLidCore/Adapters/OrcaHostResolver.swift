/// Version-gated local Orca status/worktree adapter (M3 T002).
///
/// Pure JSON parsing/normalization. No subprocesses, no network, no transcript
/// storage: only whitelisted status fields are decoded; prompt, transcript,
/// command-line, and workspace text is never read.
///
/// Gates (fail closed):
/// - Supported CLI version required for `exact` confidence; a version
///   mismatch caps confidence at `inferred` and never `exact`.
/// - Only `local` execution-host rows are local work. Stale, remote, or
///   unknown scope is rejected, never enrolled.
/// - `restoredUnconfirmed` rows stay `unknown`: a restored-but-unconfirmed
///   session can never report `working`.
/// - Snapshots older than `maxSnapshotAgeSeconds` are stale: rows are
///   rejected and previously known runs degrade to bounded `unknown`.
/// - Provider dedup by session identity: rows for sessions already claimed by
///   another adapter are rejected as duplicates. The earliest claim wins and
///   Orca yields to existing direct-adapter claims.
import Foundation

/// Tolerant semantic version: accepts "1.4.219", "v1.4.219", and trailing
/// build metadata ("1.4.219 (abc)", "1.4.219+build"). Unparseable text yields
/// nil and is treated as a version mismatch (never exact).
public struct SemanticVersion: Sendable, Equatable, Comparable, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing text: String) {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") { cleaned.removeFirst() }
        let head = cleaned.split(
            maxSplits: 1, omittingEmptySubsequences: true,
            whereSeparator: { $0 == " " || $0 == "(" || $0 == "+" || $0 == "-" }
        ).first.map(String.init) ?? ""
        let parts = head.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
            let major = Int(parts[0].prefix(while: \.isNumber)),
            let minor = Int(parts[1].prefix(while: \.isNumber))
        else { return nil }
        var patch = 0
        if parts.count >= 3 {
            guard let parsed = Int(parts[2].prefix(while: \.isNumber)) else { return nil }
            patch = parsed
        }
        guard major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.init(major, minor, patch)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Whitelisted `orca status` fields. Unknown keys are ignored.
public struct OrcaStatusPayload: Sendable, Equatable, Decodable {
    public let version: String?
    public let appRunning: Bool?
    public let runtimeState: String?
    public let runtimeReachable: Bool?
    public let graphState: String?
    public let snapshotUnixTime: Double?

    public init(
        version: String? = nil, appRunning: Bool? = nil, runtimeState: String? = nil,
        runtimeReachable: Bool? = nil, graphState: String? = nil, snapshotUnixTime: Double? = nil
    ) {
        self.version = version
        self.appRunning = appRunning
        self.runtimeState = runtimeState
        self.runtimeReachable = runtimeReachable
        self.graphState = graphState
        self.snapshotUnixTime = snapshotUnixTime
    }

    enum CodingKeys: String, CodingKey {
        case version, cliVersion, cli_version
        case appRunning, app_running
        case runtimeState, runtime_state, state
        case runtimeReachable, runtime_reachable, reachable
        case graphState, graph_state
        case snapshotUnixTime, snapshot_unix_time, snapshotTime, timestamp, takenAt, taken_at
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        version = OrcaDecode.string(box, [.version, .cliVersion, .cli_version])
        appRunning = OrcaDecode.bool(box, [.appRunning, .app_running])
        runtimeState = OrcaDecode.string(box, [.runtimeState, .runtime_state, .state])
        runtimeReachable = OrcaDecode.bool(
            box, [.runtimeReachable, .runtime_reachable, .reachable])
        graphState = OrcaDecode.string(box, [.graphState, .graph_state])
        snapshotUnixTime = OrcaDecode.double(box, [
            .snapshotUnixTime, .snapshot_unix_time, .snapshotTime, .timestamp,
            .takenAt, .taken_at,
        ])
    }
}

/// Whitelisted `orca worktree ps` row fields. Unknown keys are ignored.
public struct OrcaWorktreeRow: Sendable, Equatable, Decodable {
    public let sessionID: String
    public let runID: String?
    public let host: String?
    public let restoredUnconfirmed: Bool
    public let agentState: String?
    public let sequence: Int?
    public let sourceTime: Double?

    public init(
        sessionID: String, runID: String? = nil, host: String? = nil,
        restoredUnconfirmed: Bool = false, agentState: String? = nil,
        sequence: Int? = nil, sourceTime: Double? = nil
    ) {
        self.sessionID = sessionID
        self.runID = runID
        self.host = host
        self.restoredUnconfirmed = restoredUnconfirmed
        self.agentState = agentState
        self.sequence = sequence
        self.sourceTime = sourceTime
    }

    enum CodingKeys: String, CodingKey {
        case sessionID, sessionId, session_id, id
        case runID, runId, run_id, turnID, turn_id
        case host, executionHost, execution_host, scope, hostScope, host_scope
        case restoredUnconfirmed, restored_unconfirmed
        case agentState, agent_state, state, status
        case sequence, seq
        case sourceTime, source_time, updatedAt, updated_at
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        guard let session = OrcaDecode.string(box, [.sessionID, .sessionId, .session_id, .id])
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.sessionID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "missing session id"))
        }
        sessionID = session
        runID = OrcaDecode.string(box, [.runID, .runId, .run_id, .turnID, .turn_id])
        host = OrcaDecode.string(box, [
            .host, .executionHost, .execution_host, .scope, .hostScope, .host_scope,
        ])
        restoredUnconfirmed = OrcaDecode.bool(
            box, [.restoredUnconfirmed, .restored_unconfirmed]) ?? false
        agentState = OrcaDecode.string(box, [.agentState, .agent_state, .state, .status])
        sequence = OrcaDecode.int(box, [.sequence, .seq])
        sourceTime = OrcaDecode.double(box, [
            .sourceTime, .source_time, .updatedAt, .updated_at,
        ])
    }
}

enum OrcaDecode {
    static func string<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> String? {
        for key in keys {
            if let found: String = try? box.decode(String.self, forKey: key) { return found }
        }
        return nil
    }

    static func bool<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> Bool? {
        for key in keys {
            if let found: Bool = try? box.decode(Bool.self, forKey: key) { return found }
        }
        return nil
    }

    static func int<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> Int? {
        for key in keys {
            if let found: Int = try? box.decode(Int.self, forKey: key) { return found }
        }
        return nil
    }

    static func double<K: CodingKey>(_ box: KeyedDecodingContainer<K>, _ keys: [K]) -> Double? {
        for key in keys {
            if let found: Double = try? box.decode(Double.self, forKey: key) { return found }
            if let whole: Int = try? box.decode(Int.self, forKey: key) { return Double(whole) }
        }
        return nil
    }
}

/// A run already known to the caller, used to degrade gracefully to bounded
/// unknown when a snapshot goes stale.
public struct OrcaKnownRun: Sendable, Equatable, Hashable {
    public let sessionID: String
    public let runID: String
    public init(sessionID: String, runID: String) {
        self.sessionID = sessionID
        self.runID = runID
    }
}

/// Rejection reasons: versionMismatch caps confidence (emitted as events, not
/// rejections); all other reasons drop the row without enrolling it.
public struct OrcaRejection: Sendable, Equatable {
    public let sessionID: String
    public let reason: String
    public init(sessionID: String, reason: String) {
        self.sessionID = sessionID
        self.reason = reason
    }
}

public struct OrcaResolution: Sendable, Equatable {
    public let events: [NormalizedEvent]
    public let rejections: [OrcaRejection]
    /// Locally owned session IDs, for provider dedup by other adapters.
    public let claimedSessionIDs: Set<String>
    public let versionMismatch: Bool
    public let snapshotStale: Bool
}

public struct OrcaHostResolver: Sendable {
    public static let providerID = "orca"
    /// Minimum supported CLI version. Local-ready probe: 1.4.219.
    public static let minSupportedVersion = SemanticVersion(1, 4, 0)
    public let maxSnapshotAgeSeconds: Double

    public init(maxSnapshotAgeSeconds: Double = 15) {
        self.maxSnapshotAgeSeconds = maxSnapshotAgeSeconds
    }

    /// Maps a status snapshot plus worktree rows to normalized events.
    ///
    /// - `claimedByOtherProviders`: session IDs already owned by another
    ///   adapter; those rows are rejected as duplicates (earliest claim wins).
    /// - `previousRuns`: known runs degraded to bounded unknown when the
    ///   snapshot is stale.
    public func resolve(
        status: OrcaStatusPayload,
        rows: [OrcaWorktreeRow],
        snapshotMonotonic: Double,
        receivedMonotonic: Double,
        nowMonotonic: Double,
        sequenceBase: Int = 0,
        claimedByOtherProviders: Set<String> = [],
        previousRuns: [OrcaKnownRun] = []
    ) -> OrcaResolution {
        let parsed = status.version.flatMap { SemanticVersion(parsing: $0) }
        let versionOK = parsed.map { $0 >= Self.minSupportedVersion } ?? false
        let stale = nowMonotonic - snapshotMonotonic > maxSnapshotAgeSeconds
        if stale {
            var events: [NormalizedEvent] = []
            for known in previousRuns {
                if let event = try? NormalizedEvent(
                    provider: Self.providerID, sessionID: known.sessionID, runID: known.runID,
                    state: .unknown, evidenceKind: .lifecycle, confidence: .unknown,
                    sequence: sequenceBase, sourceTime: status.snapshotUnixTime,
                    receivedMonotonic: receivedMonotonic)
                {
                    events.append(event)
                }
            }
            let rejections = rows.map {
                OrcaRejection(sessionID: $0.sessionID, reason: "staleSnapshot")
            }
            return OrcaResolution(
                events: events, rejections: rejections, claimedSessionIDs: [],
                versionMismatch: !versionOK, snapshotStale: true)
        }
        var events: [NormalizedEvent] = []
        var rejections: [OrcaRejection] = []
        var claimed: Set<String> = []
        for (index, row) in rows.enumerated() {
            let scope = (row.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if scope != "local" {
                rejections.append(OrcaRejection(
                    sessionID: row.sessionID,
                    reason: scope.isEmpty ? "unknownScope" : "remoteScope"))
                continue
            }
            if claimedByOtherProviders.contains(row.sessionID) {
                rejections.append(OrcaRejection(
                    sessionID: row.sessionID, reason: "duplicateSession"))
                continue
            }
            var state = Self.mapAgentState(row.agentState)
            var confidence: Confidence = versionOK ? .exact : .inferred
            if row.restoredUnconfirmed {
                // Restored-but-unconfirmed sessions can never be working (or
                // any other definite state): fail closed to unknown.
                state = .unknown
                confidence = .unknown
            }
            let runID = (row.runID?.isEmpty == false) ? row.runID! : "main"
            let sequence = row.sequence ?? (sequenceBase + index)
            guard sequence >= 0,
                let event = try? NormalizedEvent(
                    provider: Self.providerID, sessionID: row.sessionID, runID: runID,
                    state: state, evidenceKind: .lifecycle, confidence: confidence,
                    sequence: sequence, sourceTime: row.sourceTime ?? status.snapshotUnixTime,
                    receivedMonotonic: receivedMonotonic)
            else {
                rejections.append(OrcaRejection(
                    sessionID: row.sessionID, reason: "invalidIdentity"))
                continue
            }
            events.append(event)
            claimed.insert(row.sessionID)
        }
        return OrcaResolution(
            events: events, rejections: rejections, claimedSessionIDs: claimed,
            versionMismatch: !versionOK, snapshotStale: false)
    }

    /// Documented-state mapping with closed fallback: unrecognized text maps
    /// to `unknown`, never to working or completed.
    public static func mapAgentState(_ raw: String?) -> TaskState {
        let folded = (raw ?? "").lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch folded {
        case "working", "running", "active", "busy", "inprogress", "executing":
            return .working
        case "waiting", "waitinginput", "needsinput", "tuiidle", "retry",
            "waitingapproval", "permissionwait", "approvalwait":
            return .waiting
        case "idle", "turnended":
            return .idle
        case "completed", "done", "finished", "exited", "success":
            return .completed
        case "failed", "error", "crashed", "exitfailed", "killed",
            "interrupted", "cancelled", "canceled":
            return .failed
        default:
            return .unknown
        }
    }
}
