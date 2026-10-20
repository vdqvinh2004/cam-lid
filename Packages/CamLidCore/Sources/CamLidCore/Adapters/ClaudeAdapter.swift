import Foundation

public struct ClaudeHookPayload: Sendable, Equatable, Decodable {
    public let hook: String
    public let sessionID: String?
    public let promptID: String?
    public let runID: String?
    public let subagentID: String?
    public let agentType: String?
    public let eventKind: String?
    /// Count only. Task IDs, descriptions, commands, and prompts are discarded.
    public let backgroundTaskCount: Int
    public let hasBackgroundTaskSnapshot: Bool
    public let hasUnknownBackgroundTaskStatus: Bool
    public let backgroundTaskSnapshotTruncated: Bool
    /// Count only. Scheduled prompts and schedules are discarded.
    public let sessionCronCount: Int
    public let notificationKind: String?

    public init(
        hook: String, sessionID: String? = nil, promptID: String? = nil,
        runID: String? = nil, subagentID: String? = nil, agentType: String? = nil,
        eventKind: String? = nil, backgroundTaskCount: Int = 0,
        hasBackgroundTaskSnapshot: Bool = false,
        hasUnknownBackgroundTaskStatus: Bool = false,
        backgroundTaskSnapshotTruncated: Bool = false,
        sessionCronCount: Int = 0, notificationKind: String? = nil
    ) {
        self.hook = hook
        self.sessionID = sessionID
        self.promptID = promptID
        self.runID = runID
        self.subagentID = subagentID
        self.agentType = agentType
        self.eventKind = eventKind
        self.backgroundTaskCount = backgroundTaskCount
        self.hasBackgroundTaskSnapshot = hasBackgroundTaskSnapshot
        self.hasUnknownBackgroundTaskStatus = hasUnknownBackgroundTaskStatus
        self.backgroundTaskSnapshotTruncated = backgroundTaskSnapshotTruncated
        self.sessionCronCount = sessionCronCount
        self.notificationKind = notificationKind
    }

    enum CodingKeys: String, CodingKey {
        case hook_event_name
        case hook, hookName, hook_name, eventName, event_name
        case sessionID, sessionId, session_id
        case prompt_id, promptId
        case runID, runId, run_id, turnID, turn_id, turnId
        case subagentID, subagentId, subagent_id
        case agent_id, agentId, agentType, agent_type
        case eventKind, event, kind, status, event_kind
        case background_tasks, backgroundTasks
        case backgroundCount, background_count
        case session_crons, sessionCrons
        case notificationKind, notificationType, notification_type, matcher
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        hook = try ClaudeDecode.string(box, [
            .hook_event_name, .hook, .hookName, .hook_name, .eventName, .event_name,
        ]) ?? ""
        sessionID = try ClaudeDecode.string(box, [.session_id, .sessionID, .sessionId])
        promptID = try ClaudeDecode.string(box, [.prompt_id, .promptId])
        runID = try ClaudeDecode.string(box, [
            .run_id, .runID, .runId, .turn_id, .turnID, .turnId,
        ])
        subagentID = try ClaudeDecode.string(box, [
            .agent_id, .subagent_id, .subagentID, .agentId, .subagentId,
        ])
        agentType = try ClaudeDecode.string(box, [.agent_type, .agentType])
        eventKind = try ClaudeDecode.string(box, [.eventKind, .event, .kind, .status, .event_kind])
        notificationKind = try ClaudeDecode.string(box, [
            .notification_type, .notificationKind, .notificationType, .matcher,
        ])

        let background = try ClaudeDecode.backgroundTasks(box)
        backgroundTaskCount = background.activeCount
        hasBackgroundTaskSnapshot = background.hasSnapshot
        hasUnknownBackgroundTaskStatus = background.hasUnknownStatus
        backgroundTaskSnapshotTruncated = background.truncated
        sessionCronCount = try ClaudeDecode.sessionCronCount(box)
    }
}

public enum ClaudeParseResult: Sendable, Equatable {
    case event(NormalizedEvent)
    case ignored(reason: String)
}

private struct ClaudeBackgroundTaskRow: Decodable {
    let id: String
    let status: String
}

private struct ClaudeSessionCronRow: Decodable {
    let id: String
    let recurring: Bool
}

private enum ClaudePayloadDecodeError: Error {
    case invalidBackgroundTasks
    case invalidSessionCrons
}

private enum ClaudeDecode {
    typealias Box = KeyedDecodingContainer<ClaudeHookPayload.CodingKeys>
    typealias Key = ClaudeHookPayload.CodingKeys

    static func string(_ box: Box, _ keys: [Key]) throws -> String? {
        for key in keys where box.contains(key) {
            return try box.decode(String.self, forKey: key)
        }
        return nil
    }

    static func backgroundTasks(_ box: Box) throws -> (
        activeCount: Int, hasSnapshot: Bool, hasUnknownStatus: Bool, truncated: Bool
    ) {
        let keys: [Key] = [.background_tasks, .backgroundTasks, .backgroundCount, .background_count]
        guard let key = keys.first(where: box.contains) else {
            return (0, false, false, false)
        }

        if let rows = try? box.decode([ClaudeBackgroundTaskRow].self, forKey: key) {
            var active = 0
            var unknown = false
            for row in rows {
                guard validID(row.id), !row.status.isEmpty,
                      row.status.count <= PolicyLimits.maxStringLength
                else { throw ClaudePayloadDecodeError.invalidBackgroundTasks }
                switch row.status.lowercased() {
                case "running":
                    active += 1
                case "completed", "complete", "succeeded", "success", "failed",
                     "cancelled", "canceled", "stopped", "terminated":
                    break
                default:
                    unknown = true
                }
            }
            return (
                min(active, PolicyLimits.maxEnrolledTasks), true, unknown,
                rows.count > PolicyLimits.maxEnrolledTasks || active > PolicyLimits.maxEnrolledTasks
            )
        }

        // Older synthetic fixtures used an integer or a string array. Keep
        // their count-only shape, but never retain the strings themselves.
        if let count = try? box.decode(Int.self, forKey: key), count >= 0 {
            return (min(count, PolicyLimits.maxEnrolledTasks), false, false,
                    count > PolicyLimits.maxEnrolledTasks)
        }
        if let values = try? box.decode([String].self, forKey: key) {
            return (min(values.count, PolicyLimits.maxEnrolledTasks), false, false,
                    values.count > PolicyLimits.maxEnrolledTasks)
        }
        throw ClaudePayloadDecodeError.invalidBackgroundTasks
    }

    static func sessionCronCount(_ box: Box) throws -> Int {
        let keys: [Key] = [.session_crons, .sessionCrons]
        guard let key = keys.first(where: box.contains) else { return 0 }
        guard let rows = try? box.decode([ClaudeSessionCronRow].self, forKey: key),
              rows.allSatisfy({ validID($0.id) })
        else { throw ClaudePayloadDecodeError.invalidSessionCrons }
        return min(rows.count, PolicyLimits.maxEnrolledTasks)
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= PolicyLimits.maxIDLength
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }
}

public struct ClaudeAdapter: Sendable {
    public static let providerID = "claude"
    public static let promptIDMinimumVersion = "2.1.196"

    public let optIn: Bool
    private let supportsPromptID: Bool
    private var nextSequence: [String: Int] = [:]
    private var sequenceOrder: [String] = []
    private var epochBySession: [String: Int] = [:]
    private var trackedSessions: [String] = []
    private var backgroundCounts: [String: Int] = [:]

    /// Disabled by default. If supplied, `providerVersion` controls whether
    /// the documented Claude `prompt_id` field may be used as exact identity.
    /// With no known version, a present prompt UUID is accepted; a missing one
    /// still falls back to an inferred session-level run.
    public init(optIn: Bool = false, providerVersion: String? = nil) {
        self.optIn = optIn
        self.supportsPromptID = providerVersion.map(Self.supportsPromptID(version:)) ?? true
    }

    public mutating func parse(json: Data, receivedMonotonic: Double) -> ClaudeParseResult {
        guard json.count <= PolicyLimits.maxEventBytes else {
            return .ignored(reason: "eventTooLarge")
        }
        let payload: ClaudeHookPayload
        do {
            payload = try JSONDecoder().decode(ClaudeHookPayload.self, from: json)
        } catch ClaudePayloadDecodeError.invalidBackgroundTasks {
            return .ignored(reason: "invalidBackgroundTasks")
        } catch ClaudePayloadDecodeError.invalidSessionCrons {
            return .ignored(reason: "invalidSessionCrons")
        } catch is DecodingError {
            return .ignored(reason: "invalidPayloadType")
        } catch {
            return .ignored(reason: "unparseable")
        }
        return parse(payload, receivedMonotonic: receivedMonotonic)
    }

    public mutating func parse(
        _ payload: ClaudeHookPayload, receivedMonotonic: Double
    ) -> ClaudeParseResult {
        guard optIn else { return .ignored(reason: "optInDisabled") }
        let hook = Self.normalized(payload.hook)
        let event = Self.normalized(payload.eventKind ?? "")
        guard !hook.isEmpty else { return .ignored(reason: "missingHookEvent") }
        if event == "interrupt" || event == "userinterrupt" || hook == "interrupt" {
            // Claude has no interrupt hook. Silence cannot prove completion.
            return .ignored(reason: "noInterruptHook")
        }
        guard Self.knownHook(hook) else { return .ignored(reason: "unknownHook") }
        guard let session = payload.sessionID, !session.isEmpty else {
            return .ignored(reason: "missingSessionID")
        }
        guard Self.validID(session) else { return .ignored(reason: "invalidSessionID") }
        registerSession(session)

        switch hook {
        case "sessionstart":
            // A resumed session only proves that the provider opened a
            // session. It does not prove that a model turn is active.
            return emitMain(
                state: .unknown, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic)
        case "userpromptsubmit":
            return emitMain(
                state: .working, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic)
        case "stop":
            let state: TaskState
            if event == "stopfailure" || event == "failure" {
                state = .failed
            } else {
                state = stopState(payload, sessionID: session)
            }
            let result = emitMain(
                state: state, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic)
            if case .event = result {
                updateBackgroundCount(for: session, payload: payload, state: state)
            }
            return result
        case "stopfailure":
            return emitMain(
                state: .failed, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic, terminal: true)
        case "subagentstart":
            return emitChild(
                state: .working, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic)
        case "subagentstop":
            return emitChild(
                state: .completed, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic, terminal: true)
        case "notification":
            guard let kind = payload.notificationKind.map(Self.normalized) else {
                return .ignored(reason: "unknownNotification")
            }
            switch kind {
            case "permissionprompt", "agentneedsinput", "elicitationdialog", "elicitationurldialog":
                return emitMain(
                    state: .waiting, payload: payload, sessionID: session,
                    receivedMonotonic: receivedMonotonic)
            case "idleprompt":
                return .ignored(reason: "idlePromptNotCompletion")
            default:
                return .ignored(reason: "unknownNotification")
            }
        case "sessionend":
            let result = emitMain(
                state: .completed, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic, terminal: true)
            if case .event = result { clearSession(session) }
            return result
        case "background":
            let result = emitMain(
                state: .working, payload: payload, sessionID: session,
                receivedMonotonic: receivedMonotonic)
            if case .event = result {
                setBackgroundCount(max(payload.backgroundTaskCount, 1), for: session)
            }
            return result
        default:
            return .ignored(reason: "unknownHook")
        }
    }

    /// Records a stream reconnect. Old sequence entries are dropped and the
    /// next event for this session carries a fresh epoch.
    public mutating func noteReconnect(sessionID: String) {
        guard Self.validID(sessionID) else { return }
        registerSession(sessionID)
        epochBySession[sessionID, default: 0] += 1
        removeSequences(sessionID: sessionID)
    }

    /// Last reported count of known-running background tasks for this session.
    public func backgroundTaskCount(sessionID: String) -> Int {
        backgroundCounts[sessionID] ?? 0
    }

    public mutating func forgetSession(_ sessionID: String) {
        clearSession(sessionID)
    }

    private struct RunIdentity {
        let id: String
        let confidence: Confidence
    }

    private struct IdentityResolution {
        let identity: RunIdentity?
        let failureReason: String?
    }

    private func identity(for payload: ClaudeHookPayload) -> IdentityResolution {
        if let promptID = payload.promptID, supportsPromptID {
            guard Self.validID(promptID) else {
                return IdentityResolution(identity: nil, failureReason: "invalidPromptID")
            }
            return IdentityResolution(
                identity: RunIdentity(id: promptID, confidence: .exact), failureReason: nil)
        }
        if let runID = payload.runID {
            guard Self.validID(runID) else {
                return IdentityResolution(identity: nil, failureReason: "invalidRunID")
            }
            return IdentityResolution(
                identity: RunIdentity(id: runID, confidence: .exact), failureReason: nil)
        }
        return IdentityResolution(
            identity: RunIdentity(id: "main", confidence: .inferred), failureReason: nil)
    }

    private mutating func emitMain(
        state: TaskState, payload: ClaudeHookPayload, sessionID: String,
        receivedMonotonic: Double, terminal: Bool = false
    ) -> ClaudeParseResult {
        let resolution = identity(for: payload)
        guard let identity = resolution.identity else {
            return .ignored(reason: resolution.failureReason ?? "invalidIdentity")
        }
        return emit(
            state: state, sessionID: sessionID, runID: identity.id, parentRunID: nil,
            confidence: identity.confidence, receivedMonotonic: receivedMonotonic,
            terminal: terminal)
    }

    private mutating func emitChild(
        state: TaskState, payload: ClaudeHookPayload, sessionID: String,
        receivedMonotonic: Double, terminal: Bool = false
    ) -> ClaudeParseResult {
        guard let childID = payload.subagentID else {
            return .ignored(reason: "missingSubagentID")
        }
        guard Self.validID(childID) else { return .ignored(reason: "invalidSubagentID") }
        let parentResolution = identity(for: payload)
        guard let parent = parentResolution.identity else {
            return .ignored(reason: parentResolution.failureReason ?? "invalidIdentity")
        }
        return emit(
            state: state, sessionID: sessionID, runID: childID, parentRunID: parent.id,
            confidence: .exact, receivedMonotonic: receivedMonotonic, terminal: terminal)
    }

    private mutating func emit(
        state: TaskState, sessionID: String, runID: String, parentRunID: String?,
        confidence: Confidence, receivedMonotonic: Double, terminal: Bool
    ) -> ClaudeParseResult {
        let key = EvidenceNormalizer.runKey(
            provider: Self.providerID, sessionID: sessionID, runID: runID)
        let sequence = nextSequence[key, default: 0]
        guard sequence < Int.max else { return .ignored(reason: "sequenceExhausted") }
        guard let event = try? NormalizedEvent(
            provider: Self.providerID, sessionID: sessionID, runID: runID,
            parentRunID: parentRunID, state: state, evidenceKind: .lifecycle,
            confidence: confidence, sequence: sequence,
            epoch: epochBySession[sessionID, default: 0],
            receivedMonotonic: receivedMonotonic)
        else { return .ignored(reason: "invalidIdentityOrTime") }

        if terminal || state == .completed || state == .failed {
            retireSequence(key)
        } else {
            storeNextSequence(sequence + 1, for: key)
        }
        return .event(event)
    }

    private func stopState(_ payload: ClaudeHookPayload, sessionID: String) -> TaskState {
        if payload.backgroundTaskCount > 0 { return .working }
        if payload.hasUnknownBackgroundTaskStatus || payload.backgroundTaskSnapshotTruncated {
            return .unknown
        }
        if payload.hasBackgroundTaskSnapshot { return .idle }
        if backgroundTaskCount(sessionID: sessionID) > 0 { return .working }
        return .idle
    }

    private mutating func updateBackgroundCount(
        for sessionID: String, payload: ClaudeHookPayload, state: TaskState
    ) {
        if payload.hasBackgroundTaskSnapshot {
            if payload.backgroundTaskCount > 0 {
                setBackgroundCount(payload.backgroundTaskCount, for: sessionID)
            } else if !payload.hasUnknownBackgroundTaskStatus && !payload.backgroundTaskSnapshotTruncated {
                setBackgroundCount(0, for: sessionID)
            }
        } else if payload.backgroundTaskCount > 0 {
            setBackgroundCount(payload.backgroundTaskCount, for: sessionID)
        } else if state == .idle || state == .failed {
            setBackgroundCount(0, for: sessionID)
        }
    }

    private mutating func setBackgroundCount(_ count: Int, for sessionID: String) {
        if count <= 0 { backgroundCounts.removeValue(forKey: sessionID) }
        else { backgroundCounts[sessionID] = min(count, PolicyLimits.maxEnrolledTasks) }
    }

    private mutating func registerSession(_ sessionID: String) {
        guard !trackedSessions.contains(sessionID) else { return }
        if trackedSessions.count >= PolicyLimits.maxEnrolledTasks {
            let oldest = trackedSessions.removeFirst()
            clearSession(oldest, removeFromOrder: false)
        }
        trackedSessions.append(sessionID)
    }

    private mutating func clearSession(_ sessionID: String, removeFromOrder: Bool = true) {
        epochBySession.removeValue(forKey: sessionID)
        backgroundCounts.removeValue(forKey: sessionID)
        removeSequences(sessionID: sessionID)
        if removeFromOrder { trackedSessions.removeAll { $0 == sessionID } }
    }

    private mutating func removeSequences(sessionID: String) {
        let prefix = "\(Self.providerID)\0\(sessionID)\0"
        let keys = sequenceOrder.filter { $0.hasPrefix(prefix) }
        for key in keys { retireSequence(key) }
    }

    private mutating func storeNextSequence(_ sequence: Int, for key: String) {
        if nextSequence[key] == nil {
            let maximum = PolicyLimits.maxEnrolledTasks * 4
            if sequenceOrder.count >= maximum {
                let oldest = sequenceOrder.removeFirst()
                nextSequence.removeValue(forKey: oldest)
            }
            sequenceOrder.append(key)
        }
        nextSequence[key] = sequence
    }

    private mutating func retireSequence(_ key: String) {
        nextSequence.removeValue(forKey: key)
        sequenceOrder.removeAll { $0 == key }
    }

    private static func knownHook(_ hook: String) -> Bool {
        ["sessionstart", "userpromptsubmit", "stop", "stopfailure", "subagentstart", "subagentstop",
         "notification", "sessionend", "background"].contains(hook)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0 != "_" && $0 != "-" }
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= PolicyLimits.maxIDLength
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func supportsPromptID(version: String) -> Bool {
        let firstToken = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let normalized = firstToken.hasPrefix("v") ? String(firstToken.dropFirst()) : firstToken
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else { return false }
        if major != 2 { return major > 2 }
        if minor != 1 { return minor > 1 }
        return patch >= 196
    }
}
