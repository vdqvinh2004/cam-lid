/// Opt-in Codex CLI hooks / `codex exec --json` adapter (M3 T004).
///
/// Pure event parsing/normalization. No subprocesses, no network, no
/// transcript storage: only whitelisted routing fields are decoded; prompt,
/// transcript, tool arguments, and terminal text are never read.
///
/// Turn-ID tracking: CLI turn hooks carry `turn_id` and subagent events carry
/// `agent_id`; events are matched to their turn, interrupts map to `failed`,
/// and a continuation/new prompt reactivates the run through a fresh event.
///
/// Explicit limitation: desktop/app-server attachment is unverified and
/// unsupported. Payloads scoped to `desktop`, `desktop-app`, or `app-server`
/// are ignored with reason `desktopUnsupported` (see
/// `desktopUnsupportedReason` / `unsupportedScopes`). Only CamLid-owned CLI
/// invocations and opt-in CLI hooks are in scope.
import Foundation

/// Whitelisted Codex routing fields. Unknown keys are ignored.
public struct CodexEventPayload: Sendable, Equatable, Decodable {
    public let hook: String
    public let sessionID: String?
    public let turnID: String?
    public let agentID: String?
    public let scope: String?
    public let isError: Bool
    public let toolOutcome: ProviderToolOutcome?
    /// Exec collaboration has independent child lifetimes not yet qualified.
    /// Inspect only the item tag, never receiver identities/prompts/messages.
    public let isCollaborationItem: Bool

    public init(
        hook: String, sessionID: String? = nil, turnID: String? = nil,
        agentID: String? = nil, scope: String? = nil, isError: Bool = false
    ) {
        self.hook = hook
        self.sessionID = sessionID
        self.turnID = turnID
        self.agentID = agentID
        self.scope = scope
        self.isError = isError
        self.toolOutcome = nil
        self.isCollaborationItem = false
    }

    enum CodingKeys: String, CodingKey {
        case hook, type, event, eventType, event_type
        case sessionID, sessionId, session_id, threadID, thread_id, threadId
        case turnID, turnId, turn_id, runID, run_id, runId
        case agentID, agentId, agent_id, subagentID, subagent_id, subagentId
        case scope, origin, client, source
        case isError, error, item
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        hook = CodexDecode.string(box, [.hook, .type, .event, .eventType, .event_type]) ?? ""
        sessionID = CodexDecode.string(box, [
            .sessionID, .sessionId, .session_id, .threadID, .thread_id, .threadId,
        ])
        turnID = CodexDecode.string(box, [.turnID, .turnId, .turn_id, .runID, .run_id, .runId])
        agentID = CodexDecode.string(box, [
            .agentID, .agentId, .agent_id, .subagentID, .subagent_id, .subagentId,
        ])
        scope = CodexDecode.string(box, [.scope, .origin, .client, .source])
        let flag = CodexDecode.bool(box, [.isError])
        let text = CodexDecode.string(box, [.error])
        isError = flag ?? (text.map { !$0.isEmpty } ?? false)
        // Decode routing/outcome fields only; never command text or output.
        let item = try? box.nestedContainer(keyedBy: ToolKeys.self, forKey: .item)
        let itemType = try? item?.decodeIfPresent(String.self, forKey: .type)
        isCollaborationItem = itemType == "collab_tool_call"
        if hook == "item.completed", itemType == "command_execution" {
            toolOutcome = ProviderToolOutcome(
                status: (try? item?.decodeIfPresent(String.self, forKey: .status)) ?? "unknown",
                exitCode: try? item?.decodeIfPresent(Int.self, forKey: .exit_code))
        } else { toolOutcome = nil }
    }
    private enum ToolKeys: String, CodingKey { case type, status, exit_code }
}

enum CodexDecode {
    // Concrete key type: keeps the multi-alias call sites type-checking fast.
    typealias Box = KeyedDecodingContainer<CodexEventPayload.CodingKeys>
    typealias Key = CodexEventPayload.CodingKeys
    static func string(_ box: Box, _ keys: [Key]) -> String? {
        for key in keys {
            if let found: String = try? box.decode(String.self, forKey: key) { return found }
        }
        return nil
    }

    static func bool(_ box: Box, _ keys: [Key]) -> Bool? {
        for key in keys {
            if let found: Bool = try? box.decode(Bool.self, forKey: key) { return found }
        }
        return nil
    }
}

public enum CodexParseResult: Sendable, Equatable {
    case event(NormalizedEvent)
    case ignored(reason: String)
}

public struct CodexAdapter: Sendable {
    public static let providerID = "codex"
    /// Explicit limitation marker: desktop/app-server attach is unverified
    /// and never tracked as exact lifecycle evidence.
    public static let desktopUnsupportedReason = "desktopUnsupported"
    public static let unsupportedScopes: Set<String> = ["desktop", "desktop-app", "app-server"]
    /// Retain replay counters rather than silently evicting old identities.
    /// A confirmed source/session boundary may explicitly release capacity.
    public static let maxRetainedIdentities = 64
    public let optIn: Bool

    private var nextSequence: [String: Int] = [:]
    private var epochBySession: [String: Int] = [:]
    private var activeTurns: [String: String] = [:]
    /// Installed-stream association (T008): `codex exec --json` emits one
    /// thread per process; only thread.started carries the ID, so subsequent
    /// session-less lines inherit the most recent thread of this stream.
    /// Interactive hook payloads always carry their own session keys and are
    /// unaffected. Reset by `forgetSession`/new thread.started.
    private var lastThreadID: String?
    public private(set) var lastToolOutcome: ProviderToolOutcome?

    /// Disabled by default: pass `optIn: true` only after explicit user choice.
    public init(optIn: Bool = false) {
        self.optIn = optIn
    }

    public mutating func parse(json: Data, receivedMonotonic: Double) -> CodexParseResult {
        guard let payload = try? JSONDecoder().decode(CodexEventPayload.self, from: json) else {
            return .ignored(reason: optIn ? "unparseable" : "optInDisabled")
        }
        return parse(payload, receivedMonotonic: receivedMonotonic)
    }

    /// Parses one `codex exec --json` JSONL line.
    public mutating func parseJSONLine(_ line: String, receivedMonotonic: Double) -> CodexParseResult {
        guard let data = line.data(using: .utf8) else {
            return .ignored(reason: optIn ? "unparseable" : "optInDisabled")
        }
        return parse(json: data, receivedMonotonic: receivedMonotonic)
    }

    public mutating func parse(_ payload: CodexEventPayload, receivedMonotonic: Double) -> CodexParseResult {
        lastToolOutcome = nil
        guard optIn else { return .ignored(reason: "optInDisabled") }
        if let scope = payload.scope?.lowercased(), Self.unsupportedScopes.contains(scope) {
            return .ignored(reason: Self.desktopUnsupportedReason)
        }
        guard !payload.isCollaborationItem else {
            return .ignored(reason: "codexCollaborationUnsupported")
        }
        lastToolOutcome = payload.toolOutcome
        let hook = payload.hook.lowercased().replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ".", with: "")
        switch hook {
        case "threadstarted":
            guard let session = payload.sessionID, !session.isEmpty else { return .ignored(reason: "missingSessionID") }
            guard (try? validateID(session)) != nil else { return .ignored(reason: "invalidIdentity") }
            let key = sessionKey(session)
            guard epochBySession[key] != nil || epochBySession.count < Self.maxRetainedIdentities else {
                return .ignored(reason: "adapterCapacityFull")
            }
            epochBySession[key] = epochBySession[key, default: 0]
            lastThreadID = session
            return .ignored(reason: "threadTracked")
        case "userpromptsubmit", "turnstarted":
            return emit(state: .working, payload: payload, receivedMonotonic: receivedMonotonic)
        case "stop", "turncompleted":
            return emit(
                state: payload.isError ? .failed : .idle, payload: payload,
                receivedMonotonic: receivedMonotonic)
        case "interrupt", "turninterrupted", "turncancelled", "turncanceled":
            return emit(state: .failed, payload: payload, receivedMonotonic: receivedMonotonic)
        case "turnfailed", "error":
            return emit(state: .failed, payload: payload, receivedMonotonic: receivedMonotonic)
        case "subagentstart", "agentstart":
            return emitChild(
                state: .working, payload: payload, receivedMonotonic: receivedMonotonic)
        case "subagentstop", "agentstop":
            return emitChild(
                state: payload.isError ? .failed : .completed, payload: payload,
                receivedMonotonic: receivedMonotonic)
        case "sessionend":
            return emit(state: .completed, payload: payload, receivedMonotonic: receivedMonotonic)
        default:
            return .ignored(reason: "unknownHook")
        }
    }

    /// Records a stream reconnect: the next events for this session carry a
    /// fresh epoch and restart at sequence 0, so replays of old numbering
    /// report `epochReset`.
    @discardableResult
    public mutating func noteReconnect(sessionID: String) -> Bool {
        guard (try? validateID(sessionID)) != nil else { return false }
        let key = sessionKey(sessionID)
        guard epochBySession[key] != nil || epochBySession.count < Self.maxRetainedIdentities else { return false }
        let epoch = epochBySession[key, default: 0]
        guard epoch < Int.max - 1 else { return false }
        epochBySession[key] = epoch + 1
        let prefix = "\(Self.providerID)\0\(sessionID)\0"
        nextSequence = nextSequence.filter { !$0.key.hasPrefix(prefix) }
        return true
    }

    /// Last turn ID observed for a session (turn-ID tracking).
    public func activeTurnID(sessionID: String) -> String? {
        activeTurns[sessionID]
    }

    public mutating func forgetSession(_ sessionID: String) {
        guard (try? validateID(sessionID)) != nil else { return }
        nextSequence = nextSequence.filter { !$0.key.hasPrefix("\(Self.providerID)\0\(sessionID)\0") }
        epochBySession.removeValue(forKey: sessionKey(sessionID))
        activeTurns.removeValue(forKey: sessionID)
        if lastThreadID == sessionID { lastThreadID = nil }
    }

    // MARK: - Private

    private func sessionKey(_ sessionID: String) -> String {
        "\(Self.providerID)\0\(sessionID)"
    }

    private mutating func emit(
        state: TaskState, payload: CodexEventPayload, receivedMonotonic: Double
    ) -> CodexParseResult {
        let session =
            ((payload.sessionID?.isEmpty == false) ? payload.sessionID : nil)
            ?? lastThreadID
        guard let session else {
            return .ignored(reason: "missingSessionID")
        }
        let turn = (payload.turnID?.isEmpty == false) ? payload.turnID! : "main"
        let result = emitEvent(session: session, run: turn, parent: nil, state: state, receivedMonotonic: receivedMonotonic)
        if case .event = result { activeTurns[session] = turn }
        return result
    }

    private mutating func emitChild(
        state: TaskState, payload: CodexEventPayload, receivedMonotonic: Double
    ) -> CodexParseResult {
        let session =
            ((payload.sessionID?.isEmpty == false) ? payload.sessionID : nil)
            ?? lastThreadID
        guard let session else {
            return .ignored(reason: "missingSessionID")
        }
        guard let child = payload.agentID, !child.isEmpty else {
            return .ignored(reason: "missingAgentID")
        }
        let parent = (payload.turnID?.isEmpty == false)
            ? payload.turnID! : (activeTurns[session] ?? "main")
        return emitEvent(session: session, run: child, parent: parent, state: state, receivedMonotonic: receivedMonotonic)
    }

    private mutating func emitEvent(
        session: String, run: String, parent: String?, state: TaskState, receivedMonotonic: Double
    ) -> CodexParseResult {
        guard (try? validateID(session)) != nil, (try? validateID(run)) != nil,
              parent.map({ (try? validateID($0)) != nil }) ?? true else {
            return .ignored(reason: "invalidIdentity")
        }
        let key = sessionKey(session)
        let runKey = EvidenceNormalizer.runKey(provider: Self.providerID, sessionID: session, runID: run)
        let sequence = nextSequence[runKey, default: 0]
        guard sequence < Int.max else { return .ignored(reason: "counterExhausted") }
        guard let event = try? NormalizedEvent(
            provider: Self.providerID, sessionID: session, runID: run,
            parentRunID: parent, state: state, evidenceKind: .lifecycle,
            confidence: .exact, sequence: sequence,
            epoch: epochBySession[key, default: 0],
            receivedMonotonic: receivedMonotonic)
        else { return .ignored(reason: "invalidIdentity") }
        guard (epochBySession[key] != nil || epochBySession.count < Self.maxRetainedIdentities),
              (nextSequence[runKey] != nil || nextSequence.count < Self.maxRetainedIdentities) else {
            return .ignored(reason: "adapterCapacityFull")
        }
        epochBySession[key] = epochBySession[key, default: 0]
        nextSequence[runKey] = sequence + 1
        lastThreadID = session
        return .event(event)
    }
}
