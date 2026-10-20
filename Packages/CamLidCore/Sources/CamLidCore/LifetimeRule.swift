import Foundation

public enum LifetimeSelectorKind: String, Codable, CaseIterable, Sendable {
    case exactExecutablePath
    case applicationBundleID
}

/// Explicit app/process lifetime selector. The rule is policy metadata only;
/// it never claims that process presence proves AI work is active or complete.
public struct LifetimeRule: Codable, Equatable, Sendable, Identifiable {
    public static let maximumRules = 20

    public let id: UUID
    public var enabled: Bool
    public let selectorKind: LifetimeSelectorKind
    public let selectorValue: String
    public var label: String

    public init(
        id: UUID = UUID(), enabled: Bool = true,
        selectorKind: LifetimeSelectorKind, selectorValue: String, label: String
    ) throws(ValidationError) {
        self.id = id
        self.enabled = enabled
        self.selectorKind = selectorKind
        self.selectorValue = selectorValue
        self.label = label
        try validate()
    }

    public func validate() throws(ValidationError) {
        guard !selectorValue.isEmpty else { throw .emptyID }
        guard selectorValue.utf8.count <= 1_024 else { throw .stringTooLong(selectorValue.count) }
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyID }
        guard label.count <= 80 else { throw .stringTooLong(label.count) }
        guard !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !hasPatternMetacharacters(selectorValue) else {
            throw .invalidIDCharacters
        }

        switch selectorKind {
        case .exactExecutablePath:
            let url = URL(fileURLWithPath: selectorValue)
            guard selectorValue.hasPrefix("/"),
                  selectorValue != "/", !selectorValue.hasSuffix("/"),
                  url.standardizedFileURL.path == selectorValue,
                  !isGenericSystemPath(selectorValue) else {
                throw .invalidIDCharacters
            }
        case .applicationBundleID:
            let parts = selectorValue.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2,
                  !selectorValue.lowercased().hasPrefix("com.apple."),
                  parts.allSatisfy(isBundleComponent) else {
                throw .invalidIDCharacters
            }
        }
    }

    public static func validateCollection(_ rules: [LifetimeRule]) throws(ValidationError) {
        guard rules.count <= maximumRules else {
            throw .outOfRange(field: "lifetimeRules", value: Double(rules.count))
        }
        var selectors = Set<String>()
        for rule in rules {
            try rule.validate()
            let key = rule.selectorKind.rawValue + "\0" + rule.selectorValue
            guard selectors.insert(key).inserted else { throw .invalidIDCharacters }
        }
    }

    private func hasPatternMetacharacters(_ value: String) -> Bool {
        value.contains(where: "*?[]{}()|^$".contains)
    }

    private func isGenericSystemPath(_ value: String) -> Bool {
        let path = value.lowercased()
        return ["/system/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/bin/", "/sbin/"]
            .contains(where: path.hasPrefix)
    }

    private func isBundleComponent(_ value: Substring) -> Bool {
        guard let first = value.utf8.first,
              first.isASCIIAlphaNumeric,
              !value.isEmpty else { return false }
        return value.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 45 }
    }
}

public struct LifetimeProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let startTime: Double
    public let userID: UInt32

    public init(pid: Int32, startTime: Double, userID: UInt32) throws(ValidationError) {
        guard pid > 0 else { throw .outOfRange(field: "pid", value: Double(pid)) }
        guard startTime.isFinite, startTime >= 0 else {
            throw .outOfRange(field: "startTime", value: startTime)
        }
        self.pid = pid
        self.startTime = startTime
        self.userID = userID
    }
}

public struct LifetimeObservedProcess: Equatable, Sendable {
    public let identity: LifetimeProcessIdentity
    public let executablePath: String?
    public let applicationBundleID: String?
    /// False only when this process appears app-bundled but its bundle identity could not be read.
    public let bundleIdentityKnown: Bool

    public init(
        identity: LifetimeProcessIdentity, executablePath: String?,
        applicationBundleID: String? = nil, bundleIdentityKnown: Bool = true
    ) throws(ValidationError) {
        if let executablePath, executablePath.utf8.count > 4_096 {
            throw .stringTooLong(executablePath.count)
        }
        if let applicationBundleID, applicationBundleID.utf8.count > 1_024 {
            throw .stringTooLong(applicationBundleID.count)
        }
        self.identity = identity
        self.executablePath = executablePath
        self.applicationBundleID = applicationBundleID
        self.bundleIdentityKnown = bundleIdentityKnown
    }
}

public struct LifetimeProcessSnapshot: Equatable, Sendable {
    public static let maximumProcesses = 4_096

    public let userID: UInt32
    public let observedAtMonotonic: Double
    public let processes: [LifetimeObservedProcess]
    public let complete: Bool

    public init(
        userID: UInt32, observedAtMonotonic: Double,
        processes: [LifetimeObservedProcess], complete: Bool
    ) throws(ValidationError) {
        guard observedAtMonotonic.isFinite, observedAtMonotonic >= 0 else {
            throw .outOfRange(field: "observedAtMonotonic", value: observedAtMonotonic)
        }
        guard processes.count <= Self.maximumProcesses else {
            throw .outOfRange(field: "processes", value: Double(processes.count))
        }
        self.userID = userID
        self.observedAtMonotonic = observedAtMonotonic
        self.processes = processes
        self.complete = complete
    }
}

public enum LifetimePresence: String, Codable, Sendable {
    case present, absent, unknown
}

public struct LifetimeRuleStatus: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let label: String
    public let presence: LifetimePresence
    public let processCount: Int?
    public let reasonCode: String?
}

public struct LifetimePolicyState: Equatable, Sendable {
    public let statuses: [LifetimeRuleStatus]
    public let hasActiveRule: Bool
    public let hasUnknownHold: Bool
    public let suppressesAutoCompletion: Bool

    public var holdReason: String? {
        if hasActiveRule { "lifetimeRuleActive" }
        else if hasUnknownHold { "lifetimeRuleUnknown" }
        else { nil }
    }

    public func status(for ruleID: UUID) -> LifetimeRuleStatus? {
        statuses.first { $0.id == ruleID }
    }
}

/// Exact process presence can hold an existing Auto session. It never becomes
/// AI task evidence or authorizes completion sleep after the process disappears.
public struct LifetimeRuleTracker: Sendable {
    private struct RuleState: Sendable {
        var selectorKind: LifetimeSelectorKind
        var selectorValue: String
        var presence: LifetimePresence = .unknown
        var processIdentities: Set<LifetimeProcessIdentity> = []
        var firstAbsentAt: Double?
        var absentObservations = 0
        var unknownSince: Double?
        var lastPresentAt: Double?
        var lastObservationAt: Double?
        var completionSuppressed = false
        var suppressionEpoch: String?
        var suppressionResetPending = false
        var reasonCode: String? = "processScanUnknown"
        var processCount: Int?

        init(rule: LifetimeRule, now: Double) {
            selectorKind = rule.selectorKind
            selectorValue = rule.selectorValue
            unknownSince = now
        }
    }

    private var states: [UUID: RuleState] = [:]
    private var sessionID: String?
    private var hasObservedSession = false

    public init() {}

    public mutating func update(
        rules: [LifetimeRule], snapshot: LifetimeProcessSnapshot?, now: Double,
        sessionID: String?, exactTaskEpoch: String?, waitRetentionSeconds: Double
    ) throws(ValidationError) -> LifetimePolicyState {
        guard now.isFinite, now >= 0 else {
            throw .outOfRange(field: "now", value: now)
        }
        guard waitRetentionSeconds.isFinite, waitRetentionSeconds >= 0 else {
            throw .outOfRange(field: "waitRetentionSeconds", value: waitRetentionSeconds)
        }
        try LifetimeRule.validateCollection(rules)

        if self.sessionID != sessionID {
            let newExplicitSession = sessionID != nil && hasObservedSession
            for id in Array(states.keys) {
                states[id]?.completionSuppressed = false
                states[id]?.suppressionEpoch = nil
                states[id]?.suppressionResetPending = newExplicitSession
            }
            self.sessionID = sessionID
        }
        if sessionID != nil { hasObservedSession = true }

        let activeRules = rules.filter(\.enabled)
        let activeIDs = Set(activeRules.map(\.id))
        states = states.filter { activeIDs.contains($0.key) }
        var statuses: [LifetimeRuleStatus] = []

        for rule in activeRules {
            var state = states[rule.id].flatMap {
                $0.selectorKind == rule.selectorKind && $0.selectorValue == rule.selectorValue ? $0 : nil
            } ?? RuleState(rule: rule, now: now)

            let sampleIsFresh = snapshot.map {
                $0.observedAtMonotonic <= now && now - $0.observedAtMonotonic <= 5
            } ?? false
            guard let snapshot, snapshot.complete, sampleIsFresh else {
                markUnknown(&state, reason: snapshot == nil ? "processScanUnavailable"
                    : (snapshot?.complete == false ? "processScanIncomplete" : "telemetryStale"),
                    now: now, exactTaskEpoch: exactTaskEpoch)
                statuses.append(status(for: rule, state: state))
                states[rule.id] = state
                continue
            }

            guard state.lastObservationAt.map({ snapshot.observedAtMonotonic > $0 }) ?? true else {
                if now - snapshot.observedAtMonotonic > 5 {
                    markUnknown(&state, reason: "telemetryStale", now: now, exactTaskEpoch: exactTaskEpoch)
                }
                statuses.append(status(for: rule, state: state))
                states[rule.id] = state
                continue
            }
            state.lastObservationAt = snapshot.observedAtMonotonic

            let sameUserProcesses = snapshot.processes.filter { $0.identity.userID == snapshot.userID }
            let matching = sameUserProcesses.filter { process in
                guard let path = process.executablePath else { return false }
                switch rule.selectorKind {
                case .exactExecutablePath:
                    return path == rule.selectorValue
                case .applicationBundleID:
                    return process.bundleIdentityKnown && process.applicationBundleID == rule.selectorValue
                }
            }
            if !matching.isEmpty {
                state.presence = .present
                state.processIdentities = Set(matching.map(\.identity))
                state.firstAbsentAt = nil
                state.absentObservations = 0
                state.unknownSince = nil
                state.lastPresentAt = snapshot.observedAtMonotonic
                state.completionSuppressed = true
                state.suppressionResetPending = false
                if state.suppressionEpoch == nil { state.suppressionEpoch = exactTaskEpoch }
                state.reasonCode = nil
                state.processCount = matching.count
            } else {
                let sameIdentityChangedSelector = sameUserProcesses.contains {
                    state.processIdentities.contains($0.identity)
                }
                let pathUnavailable = sameUserProcesses.contains { $0.executablePath == nil }
                let bundleUnavailable = rule.selectorKind == .applicationBundleID
                    && sameUserProcesses.contains { !$0.bundleIdentityKnown }

                if sameIdentityChangedSelector {
                    markUnknown(&state, reason: "selectorChanged", now: now, exactTaskEpoch: exactTaskEpoch)
                } else if pathUnavailable || bundleUnavailable {
                    markUnknown(&state, reason: pathUnavailable ? "processPathUnknown" : "bundleIdentityUnknown",
                        now: now, exactTaskEpoch: exactTaskEpoch)
                } else {
                    if state.firstAbsentAt == nil {
                        state.firstAbsentAt = snapshot.observedAtMonotonic
                        state.absentObservations = 1
                    } else {
                        state.absentObservations += 1
                    }
                    if state.unknownSince == nil {
                        state.unknownSince = state.lastPresentAt ?? snapshot.observedAtMonotonic
                    }
                    if !state.suppressionResetPending {
                        state.completionSuppressed = true
                        if state.suppressionEpoch == nil { state.suppressionEpoch = exactTaskEpoch }
                    }
                    if state.absentObservations >= 2,
                       snapshot.observedAtMonotonic - (state.firstAbsentAt ?? snapshot.observedAtMonotonic) >= 5 {
                        state.presence = .absent
                        state.processIdentities = []
                        state.unknownSince = nil
                        state.reasonCode = nil
                        state.processCount = 0
                        if state.suppressionResetPending {
                            state.completionSuppressed = false
                            state.suppressionEpoch = nil
                            state.suppressionResetPending = false
                        } else if let exactTaskEpoch, exactTaskEpoch != state.suppressionEpoch {
                            state.completionSuppressed = false
                            state.suppressionEpoch = nil
                        }
                    } else {
                        state.presence = .unknown
                        state.reasonCode = "absenceUnconfirmed"
                        state.processCount = nil
                    }
                }
            }
            statuses.append(status(for: rule, state: state))
            states[rule.id] = state
        }

        let hasActiveRule = statuses.contains { $0.presence == .present }
        let hasUnknownHold = statuses.contains { status in
            guard status.presence == .unknown,
                  let state = states[status.id], let unknownSince = state.unknownSince else { return false }
            return now < unknownSince + waitRetentionSeconds
        }
        return LifetimePolicyState(statuses: statuses, hasActiveRule: hasActiveRule,
            hasUnknownHold: hasUnknownHold,
            suppressesAutoCompletion: states.values.contains(where: \.completionSuppressed))
    }

    private func status(for rule: LifetimeRule, state: RuleState) -> LifetimeRuleStatus {
        LifetimeRuleStatus(id: rule.id, label: rule.label, presence: state.presence,
            processCount: state.processCount, reasonCode: state.reasonCode)
    }

    private func markUnknown(
        _ state: inout RuleState, reason: String, now: Double, exactTaskEpoch: String?
    ) {
        if state.presence == .present, state.unknownSince == nil {
            state.unknownSince = state.lastPresentAt ?? now
        } else if state.unknownSince == nil {
            state.unknownSince = now
        }
        state.presence = .unknown
        state.reasonCode = reason
        state.processCount = nil
        state.completionSuppressed = true
        state.suppressionResetPending = false
        if state.suppressionEpoch == nil { state.suppressionEpoch = exactTaskEpoch }
    }
}

private extension UInt8 {
    var isASCIIAlphaNumeric: Bool {
        (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self)
    }
}
