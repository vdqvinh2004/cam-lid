/// Shared entity model. Bounds from docs/planning/domain-model.md.
/// T002: batteryPercent/cpuPercent 0–100 optional, session/run IDs nonempty ≤128,
/// strings ≤256. Unknown/missing is never healthy and never zero.
import Foundation
public enum PolicyLimits {
    public static let maxIDLength = 128
    public static let maxStringLength = 256
    public static let maxEnrolledTasks = 20
    public static let maxEventBytes = 64 * 1024
}

public enum ValidationError: Error, Equatable, Sendable {
    case emptyID
    case idTooLong(Int)
    case invalidIDCharacters
    case stringTooLong(Int)
    case outOfRange(field: String, value: Double)
}

public func validateID(_ value: String) throws(ValidationError) {
    guard !value.isEmpty else { throw .emptyID }
    guard value.count <= PolicyLimits.maxIDLength else { throw .idTooLong(value.count) }
    guard value.rangeOfCharacter(from: .controlCharacters) == nil else { throw .invalidIDCharacters }
}

public func validateString(_ value: String) throws(ValidationError) {
    guard value.count <= PolicyLimits.maxStringLength else { throw .stringTooLong(value.count) }
}

public func validatePercent(_ value: Double, field: String) throws(ValidationError) {
    guard value.isFinite, (0...100).contains(value) else {
        throw .outOfRange(field: field, value: value)
    }
}

public enum RequestedMode: String, Sendable, Codable, CaseIterable {
    case off, auto, timed, manual
}

public enum EffectiveState: String, Sendable, Codable, CaseIterable {
    case off, ready, protected, completionGrace, safetyStopped, expired, unavailable, recoveryRequired
}

public enum TaskState: String, Sendable, Codable, CaseIterable {
    case working, waiting, idle, completed, failed, unknown
}

public enum EvidenceKind: String, Sendable, Codable, CaseIterable {
    case lifecycle, wrapper, process
}

public enum Confidence: String, Sendable, Codable, CaseIterable {
    case exact, inferred, unknown
}

public enum PowerSource: String, Sendable, Codable, CaseIterable {
    case ac, battery, unknown
}

public enum ThermalPressure: String, Sendable, Codable, CaseIterable {
    case nominal, fair, serious, critical, unknown
}

public enum LidState: String, Sendable, Codable, CaseIterable {
    case open, closed, unknown
}

public enum DisplayState: String, Sendable, Codable, CaseIterable {
    case asleep, awake, disconnected, unknown
}

public struct AgentTask: Sendable, Codable, Equatable {
    public let id: String
    public let sessionID: String
    public let runID: String
    public let parentRunID: String?
    public var state: TaskState
    public let evidenceKind: EvidenceKind
    public let confidence: Confidence
    /// Monotonic second through which `waiting` still holds the session.
    public let waitUntilMonotonic: Double?
    /// Monotonic second through which `unknown` (previously working) still holds.
    public let unknownUntilMonotonic: Double?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, runID, parentRunID, state, evidenceKind, confidence,
            waitUntilMonotonic, unknownUntilMonotonic
    }

    /// Decoding validates exactly like the throwing initializer: synthesized
    /// decoding alone would bypass `validateID`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let sessionID = try container.decode(String.self, forKey: .sessionID)
        let runID = try container.decode(String.self, forKey: .runID)
        let parentRunID = try container.decodeIfPresent(String.self, forKey: .parentRunID)
        let state = try container.decode(TaskState.self, forKey: .state)
        let evidenceKind = try container.decode(EvidenceKind.self, forKey: .evidenceKind)
        let confidence = try container.decode(Confidence.self, forKey: .confidence)
        let waitUntil = try container.decodeIfPresent(Double.self, forKey: .waitUntilMonotonic)
        let unknownUntil = try container.decodeIfPresent(
            Double.self, forKey: .unknownUntilMonotonic)
        do {
            try self.init(
                id: id, sessionID: sessionID, runID: runID, parentRunID: parentRunID,
                state: state, evidenceKind: evidenceKind, confidence: confidence,
                waitUntilMonotonic: waitUntil, unknownUntilMonotonic: unknownUntil
            )
        } catch let invalid {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AgentTask validation failed: \(invalid)"))
        }
    }

    public init(
        id: String, sessionID: String, runID: String, parentRunID: String? = nil,
        state: TaskState, evidenceKind: EvidenceKind, confidence: Confidence,
        waitUntilMonotonic: Double? = nil, unknownUntilMonotonic: Double? = nil
    ) throws(ValidationError) {
        try validateID(id)
        try validateID(sessionID)
        try validateID(runID)
        if let parent = parentRunID { try validateID(parent) }
        for (field, deadline) in [("waitUntilMonotonic", waitUntilMonotonic), ("unknownUntilMonotonic", unknownUntilMonotonic)] {
            if let deadline, !deadline.isFinite || deadline < 0 {
                throw ValidationError.outOfRange(field: field, value: deadline)
            }
        }
        self.id = id
        self.sessionID = sessionID
        self.runID = runID
        self.parentRunID = parentRunID
        self.state = state
        self.evidenceKind = evidenceKind
        self.confidence = confidence
        self.waitUntilMonotonic = waitUntilMonotonic
        self.unknownUntilMonotonic = unknownUntilMonotonic
    }
}

public struct HealthSnapshot: Sendable, Codable, Equatable {
    public let lid: LidObservation?
    public let temperature: TemperatureObservation
    public let batteryPercent: Double?
    public let powerSource: PowerSource
    public let thermalPressure: ThermalPressure
    public let cpuPercent: Double?
    public let lidState: LidState
    public let internalDisplayState: DisplayState
    public let capabilityVerified: Bool

    private enum CodingKeys: String, CodingKey {
        case temperature, lid, batteryPercent, powerSource, thermalPressure, cpuPercent, lidState,
            internalDisplayState, capabilityVerified
    }

    /// Decoding validates exactly like the throwing initializer: synthesized
    /// decoding alone would bypass `validatePercent`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let batteryPercent = try container.decodeIfPresent(
            Double.self, forKey: .batteryPercent)
        let powerSource = try container.decode(PowerSource.self, forKey: .powerSource)
        let thermalPressure = try container.decode(
            ThermalPressure.self, forKey: .thermalPressure)
        let cpuPercent = try container.decodeIfPresent(Double.self, forKey: .cpuPercent)
        let lidState = try container.decode(LidState.self, forKey: .lidState)
        let internalDisplayState = try container.decode(
            DisplayState.self, forKey: .internalDisplayState)
        let capabilityVerified = try container.decode(Bool.self, forKey: .capabilityVerified)
        do {
            try self.init(
                batteryPercent: batteryPercent, powerSource: powerSource,
                thermalPressure: thermalPressure, cpuPercent: cpuPercent,
                lidState: lidState, internalDisplayState: internalDisplayState,
                capabilityVerified: capabilityVerified, lid: try container.decodeIfPresent(LidObservation.self, forKey: .lid),
                temperature: try container.decodeIfPresent(TemperatureObservation.self, forKey: .temperature) ?? .unsupported
            )
        } catch let invalid {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "HealthSnapshot validation failed: \(invalid)"))
        }
    }

    public init(
        batteryPercent: Double? = nil, powerSource: PowerSource = .unknown,
        thermalPressure: ThermalPressure = .unknown, cpuPercent: Double? = nil,
        lidState: LidState = .unknown, internalDisplayState: DisplayState = .unknown,
        capabilityVerified: Bool = false, lid: LidObservation? = nil, temperature: TemperatureObservation = .unsupported
    ) throws(ValidationError) {
        if let battery = batteryPercent { try validatePercent(battery, field: "batteryPercent") }
        if let cpu = cpuPercent { try validatePercent(cpu, field: "cpuPercent") }
        self.lid = lid
        self.temperature = temperature
        self.batteryPercent = batteryPercent
        self.powerSource = powerSource
        self.thermalPressure = thermalPressure
        self.cpuPercent = cpuPercent
        self.lidState = lid?.state ?? lidState
        self.internalDisplayState = internalDisplayState
        self.capabilityVerified = capabilityVerified
    }
}

public struct ProtectionSession: Sendable, Codable, Equatable {
    public let id: String
    public var requestedMode: RequestedMode
    public var effectiveState: EffectiveState
    public var armedClosedLid: Bool
    public var taskIDs: Set<String>
    public let startedAtMonotonic: Double
    /// Nil for Infinite. Finite deadlines never extend for fresh work or preference edits.
    public var capDeadlineMonotonic: Double?
    public var graceDeadlineMonotonic: Double?
    public var latchedSafetyStop: Bool
    public var stopReasons: [String]
    public var stateRevision: Int

    private enum CodingKeys: String, CodingKey {
        case id, requestedMode, effectiveState, armedClosedLid, taskIDs,
            startedAtMonotonic, capDeadlineMonotonic, graceDeadlineMonotonic,
            latchedSafetyStop, stopReasons, stateRevision
    }

    /// Decoding validates the session/run IDs exactly like the throwing
    /// initializer: synthesized decoding alone would bypass `validateID`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let requestedMode = try container.decode(RequestedMode.self, forKey: .requestedMode)
        let effectiveState = try container.decode(EffectiveState.self, forKey: .effectiveState)
        let armedClosedLid = try container.decode(Bool.self, forKey: .armedClosedLid)
        let taskIDs = try container.decode(Set<String>.self, forKey: .taskIDs)
        let startedAt = try container.decode(Double.self, forKey: .startedAtMonotonic)
        let capDeadline = try container.decodeIfPresent(Double.self, forKey: .capDeadlineMonotonic)
        let graceDeadline = try container.decodeIfPresent(
            Double.self, forKey: .graceDeadlineMonotonic)
        let latchedSafetyStop = try container.decode(Bool.self, forKey: .latchedSafetyStop)
        let stopReasons = try container.decode([String].self, forKey: .stopReasons)
        let stateRevision = try container.decode(Int.self, forKey: .stateRevision)
        do {
            try validateID(id)
            for taskID in taskIDs { try validateID(taskID) }
            try Self.validateTimes(start: startedAt, cap: capDeadline, grace: graceDeadline, mode: requestedMode)
            guard taskIDs.count <= PolicyLimits.maxEnrolledTasks else {
                throw ValidationError.outOfRange(field: "taskIDs", value: Double(taskIDs.count))
            }
            guard stateRevision >= 0 else { throw ValidationError.outOfRange(field: "stateRevision", value: Double(stateRevision)) }
            guard stopReasons.count <= 32 else { throw ValidationError.outOfRange(field: "stopReasons", value: Double(stopReasons.count)) }
            for reason in stopReasons { try validateString(reason) }
        } catch let invalid {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "ProtectionSession validation failed: \(invalid)"))
        }
        // Decoding preserves state only after validating identities and deadlines.
        self.id = id
        self.requestedMode = requestedMode
        self.effectiveState = effectiveState
        self.armedClosedLid = armedClosedLid
        self.taskIDs = taskIDs
        self.startedAtMonotonic = startedAt
        self.capDeadlineMonotonic = capDeadline
        self.graceDeadlineMonotonic = graceDeadline
        self.latchedSafetyStop = latchedSafetyStop
        self.stopReasons = stopReasons
        self.stateRevision = stateRevision
    }

    public init(
        id: String, requestedMode: RequestedMode, armedClosedLid: Bool,
        startedAtMonotonic: Double, capDeadlineMonotonic: Double?
    ) throws(ValidationError) {
        try validateID(id)
        try Self.validateTimes(start: startedAtMonotonic, cap: capDeadlineMonotonic, grace: nil, mode: requestedMode)
        self.id = id
        self.requestedMode = requestedMode
        self.effectiveState = requestedMode == .off ? .off : .ready
        self.armedClosedLid = armedClosedLid
        self.taskIDs = []
        self.startedAtMonotonic = startedAtMonotonic
        self.capDeadlineMonotonic = capDeadlineMonotonic
        self.graceDeadlineMonotonic = nil
        self.latchedSafetyStop = false
        self.stopReasons = []
        self.stateRevision = 0
    }

    private static func validateTimes(start: Double, cap: Double?, grace: Double?, mode: RequestedMode) throws(ValidationError) {
        guard start.isFinite, start >= 0 else { throw ValidationError.outOfRange(field: "startedAtMonotonic", value: start) }
        if let cap {
            guard cap.isFinite, cap >= start else { throw ValidationError.outOfRange(field: "capDeadlineMonotonic", value: cap) }
        } else if mode != .timed && mode != .manual {
            throw ValidationError.outOfRange(field: "capDeadlineMonotonic", value: -1)
        }
        if let grace, !grace.isFinite || grace < 0 { throw ValidationError.outOfRange(field: "graceDeadlineMonotonic", value: grace) }
    }
}

/// Safety input computed by SafetyPolicy (T011). The engine latches on any reason.
public struct SafetySignal: Sendable, Equatable {
    public let reasons: [String]
    public static let clear = SafetySignal(reasons: [])
    public init(reasons: [String]) { self.reasons = reasons; }
}

public enum EnrollmentError: Error, Equatable, Sendable {
    case overLimit(limit: Int, active: Int)
    case invalidID
}

/// Bounded enrollment set. Rejects excess visibly, never evicts existing work.
/// T014 (shared half).
public struct EnrollmentSet: Sendable, Equatable {
    public private(set) var ids: [String] = []

    public init() {}

    public var count: Int { ids.count }

    public mutating func enroll(_ id: String) throws(EnrollmentError) {
        guard !id.isEmpty else { throw .invalidID }
        guard id.count <= PolicyLimits.maxIDLength else { throw .invalidID }
        if ids.contains(id) { return }  // idempotent re-enrollment
        guard ids.count < PolicyLimits.maxEnrolledTasks else {
            throw .overLimit(limit: PolicyLimits.maxEnrolledTasks, active: ids.count)
        }
        ids.append(id)
    }

    public mutating func release(_ id: String) {
        ids.removeAll { $0 == id }
    }
}
