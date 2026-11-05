import Foundation

public enum DiagnosticCoverage: String, Codable, Sendable { case complete, partial, unavailable }
public enum ProtectionOutcome: String, Codable, Sendable { case notRequested, unsupported, requested, verified, restoring, failed }
public enum SleepEffect: String, Codable, Sendable {
    case systemIdle, displayIdle, userActivity, global, kernel, unknown
    public static func assertion(_ type: String) -> Self {
        switch type {
        case "PreventUserIdleSystemSleep", "PreventSystemSleep",
             "BackgroundTask", "ApplePushServiceTask", "NetworkClientActive", "SystemIsActive":
            .systemIdle
        case "PreventUserIdleDisplaySleep", "InternalPreventDisplaySleep": .displayIdle
        case "UserIsActive": .userActivity
        default: .unknown
        }
    }
    public var title: String {
        switch self {
        case .systemIdle: "Keeps system awake"
        case .displayIdle: "Keeps system and display awake"
        case .userActivity: "Recent input postpones display sleep"
        case .global: "System-wide sleep setting"
        case .kernel: "Device or kernel sleep request"
        case .unknown: "Other power activity — effect unknown"
        }
    }
}
public struct DiagnosticBlocker: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var effect: SleepEffect
    public var source: String
    public var owner: String?
    public var pid: Int?
    public var explanation: String
    public init(id: String, type: String, effect: SleepEffect, source: String,
                owner: String? = nil, pid: Int? = nil, explanation: String) {
        self.id = id; self.type = String(type.prefix(160)); self.effect = effect
        self.source = source; self.owner = owner.map { String($0.prefix(160)) }; self.pid = pid
        self.explanation = explanation
    }
}
public struct DiagnosticSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var observedAt: Date
    public var coverage: [String: DiagnosticCoverage]
    public var errors: [String]
    public var configuredMode: RequestedMode
    public var activeSessionMode: RequestedMode?
    public var protection: ProtectionOutcome
    public var restoration: String
    public var blockers: [DiagnosticBlocker]
    /// Process names macOS itself listed in `sleep ... (sleep prevented by ...)`.
    /// Empty when the line said nothing is preventing sleep *or* when it could
    /// not be read; check `coverage["preventing"]` to tell those apart.
    public var preventedBy: [String]
    public init(observedAt: Date = Date(), coverage: [String: DiagnosticCoverage] = [:], errors: [String] = [],
                configuredMode: RequestedMode = .off, activeSessionMode: RequestedMode? = nil,
                protection: ProtectionOutcome = .notRequested, restoration: String = "noPowerResourcesOwned",
                blockers: [DiagnosticBlocker] = [], preventedBy: [String] = []) {
        self.observedAt = observedAt; self.coverage = coverage; self.errors = errors
        self.configuredMode = configuredMode; self.activeSessionMode = activeSessionMode
        self.protection = protection; self.restoration = restoration; self.blockers = blockers
        self.preventedBy = preventedBy
    }
    public var hasCoverage: Bool { coverage.values.contains { $0 != .unavailable } }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, observedAt, coverage, errors, configuredMode, activeSessionMode
        case protection, restoration, blockers, preventedBy
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(observedAt, forKey: .observedAt)
        try values.encode(coverage, forKey: .coverage)
        try values.encode(errors, forKey: .errors)
        try values.encode(configuredMode, forKey: .configuredMode)
        try values.encode(activeSessionMode, forKey: .activeSessionMode)
        try values.encode(protection, forKey: .protection)
        try values.encode(restoration, forKey: .restoration)
        try values.encode(blockers, forKey: .blockers)
        try values.encode(preventedBy, forKey: .preventedBy)
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        coverage = try values.decode([String: DiagnosticCoverage].self, forKey: .coverage)
        errors = try values.decode([String].self, forKey: .errors)
        configuredMode = try values.decode(RequestedMode.self, forKey: .configuredMode)
        activeSessionMode = try values.decodeIfPresent(RequestedMode.self, forKey: .activeSessionMode)
        protection = try values.decode(ProtectionOutcome.self, forKey: .protection)
        restoration = try values.decode(String.self, forKey: .restoration)
        blockers = try values.decode([DiagnosticBlocker].self, forKey: .blockers)
        preventedBy = try values.decodeIfPresent([String].self, forKey: .preventedBy) ?? []
    }
    public func redacted() -> Self {
        var result = self
        result.preventedBy = []
        for index in result.blockers.indices {
            result.blockers[index].id = "request-\(index)"
            result.blockers[index].owner = nil; result.blockers[index].pid = nil
            if result.blockers[index].effect == .unknown { result.blockers[index].type = "UnknownAssertion" }
        }
        return result
    }
    public func boundedJSON(redacted: Bool = true) throws -> Data {
        var snapshot = redacted ? self.redacted() : self
        if snapshot.blockers.count > 256 {
            snapshot.blockers = Array(snapshot.blockers.prefix(256))
            snapshot.errors.append("ownerRowsTruncated")
            snapshot.coverage["userAssertions"] = .partial
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(snapshot)
        // Leave space for the CLIResult and local wire envelopes.
        while data.count > 28_000, !snapshot.blockers.isEmpty {
            snapshot.blockers.removeLast()
            if !snapshot.errors.contains("responseTruncated") { snapshot.errors.append("responseTruncated") }
            snapshot.coverage["userAssertions"] = .partial
            data = try encoder.encode(snapshot)
        }
        _ = try BoundedPayload(data)
        return data
    }
}

public enum NotificationCategory: String, Codable, CaseIterable, Sendable {
    case completion, failure, safety, restoration
    public var title: String {
        switch self { case .completion: "Work finished"; case .failure: "Work failed"; case .safety: "Safety stops"; case .restoration: "Recovery problems" }
    }
}

/// Opaque, one-use view of the current command admission. Each renewal returns
/// a new sequence so an older receipt cannot renew or finish the same job.
public struct CommandReceipt: Codable, Sendable, Equatable {
    public let id: UUID
    public let sequence: UInt64
    public let expiresAtMonotonic: Double

    public func validate() throws(IPCError) {
        guard expiresAtMonotonic.isFinite, expiresAtMonotonic >= 0 else {
            throw .invalidInput("invalidAdmissionReceipt")
        }
    }
}

/// The only client supplied metadata for a protected command. The executable
/// argv and all child IO stay in the client process.
public struct AdmitCommandRequest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let label: String

    public init(label: String, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.label = label
    }

    public func validate() throws(IPCError) {
        guard schemaVersion == 1,
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.utf8.count <= 80,
              !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw .invalidInput("invalidAdmissionRequest")
        }
    }
}

public struct RenewCommandRequest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let receipt: CommandReceipt

    public init(receipt: CommandReceipt, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.receipt = receipt
    }

    public func validate() throws(IPCError) {
        guard schemaVersion == 1 else { throw .invalidInput("invalidRenewalRequest") }
        try receipt.validate()
    }
}

public struct FinishCommandRequest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let receipt: CommandReceipt

    public init(receipt: CommandReceipt, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.receipt = receipt
    }

    public func validate() throws(IPCError) {
        guard schemaVersion == 1 else { throw .invalidInput("invalidFinishRequest") }
        try receipt.validate()
    }
}

/// `dryRun` is the only sleep request option. There is no force bypass or
/// caller supplied policy, duration, command, or output field.
public struct SleepCommandRequest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let dryRun: Bool

    public init(dryRun: Bool, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.dryRun = dryRun
    }

    public func validate() throws(IPCError) {
        guard schemaVersion == 1 else { throw .invalidInput("invalidSleepRequest") }
    }
}

/// In-memory command holds. The app process owns this value; crash recovery and
/// the underlying power lease remain owned by the qualified M2 backend.
public struct CommandAdmissions: Sendable {
    private struct Entry: Sendable {
        let uid: UInt32
        let bootID: String
        let sessionID: String
        let generation: UInt64
        var sequence: UInt64
        var expiresAtMonotonic: Double
    }

    public static let maximumJobs = 20
    public static let renewalInterval: Double = 10
    public static let ownershipLifetime: Double = 30

    private var entries: [UUID: Entry] = [:]

    public init() {}

    public var count: Int { entries.count }

    public mutating func admit(
        label: String,
        session: ProtectionSession?,
        uid: UInt32,
        bootID: String,
        generation: UInt64,
        backendVerified: Bool,
        safetyClear: Bool,
        now: Double
    ) throws(IPCError) -> CommandReceipt {
        expire(now: now)
        guard let session,
              PolicyEngine.mayAdmitCommand(
                session: session, backendVerified: backendVerified,
                safetyClear: safetyClear, nowMonotonic: now
              ) else {
            throw .policyDenied("commandAdmissionDenied")
        }
        try AdmitCommandRequest(label: label).validate()
        guard !bootID.isEmpty, bootID.utf8.count <= 128,
              generation > 0, now.isFinite, now >= 0,
              now + Self.ownershipLifetime > now else {
            throw .invalidInput("invalidAdmission")
        }
        guard entries.count < Self.maximumJobs else {
            throw .policyDenied("commandAdmissionCapacity")
        }

        let id = UUID()
        let expiry = now + Self.ownershipLifetime
        entries[id] = Entry(
            uid: uid, bootID: bootID, sessionID: session.id, generation: generation,
            sequence: 0, expiresAtMonotonic: expiry
        )
        return CommandReceipt(id: id, sequence: 0, expiresAtMonotonic: expiry)
    }

    public mutating func renew(
        _ receipt: CommandReceipt,
        session: ProtectionSession?,
        uid: UInt32,
        bootID: String,
        generation: UInt64,
        backendVerified: Bool,
        safetyClear: Bool,
        now: Double
    ) throws(IPCError) -> CommandReceipt {
        guard let entry = entries[receipt.id] else {
            throw .policyDenied("commandAdmissionStale")
        }
        guard entry.uid == uid else { throw .unauthorized }
        guard entry.bootID == bootID, entry.generation == generation,
              let session, entry.sessionID == session.id else {
            throw .policyDenied("commandAdmissionStale")
        }
        guard receipt.sequence == entry.sequence,
              receipt.expiresAtMonotonic == entry.expiresAtMonotonic else {
            throw .policyDenied("commandAdmissionStale")
        }
        guard now.isFinite, now >= 0, now < entry.expiresAtMonotonic else {
            entries.removeValue(forKey: receipt.id)
            throw .policyDenied("commandAdmissionStale")
        }
        guard PolicyEngine.mayAdmitCommand(
            session: session, backendVerified: backendVerified,
            safetyClear: safetyClear, nowMonotonic: now
        ) else {
            entries.removeValue(forKey: receipt.id)
            throw .policyDenied("commandAdmissionRevoked")
        }
        guard entry.sequence < UInt64.max,
              now + Self.ownershipLifetime > now else {
            entries.removeValue(forKey: receipt.id)
            throw .invalidInput("invalidRenewal")
        }
        let next = CommandReceipt(
            id: receipt.id, sequence: entry.sequence + 1,
            expiresAtMonotonic: now + Self.ownershipLifetime
        )
        entries[receipt.id]?.sequence = next.sequence
        entries[receipt.id]?.expiresAtMonotonic = next.expiresAtMonotonic
        return next
    }

    /// Finishes only the current receipt for the authenticated job and scope.
    /// A failed spawn uses this same path before returning its launch error.
    public mutating func finish(
        _ receipt: CommandReceipt,
        uid: UInt32,
        bootID: String,
        generation: UInt64,
        now: Double
    ) throws(IPCError) {
        guard let entry = entries[receipt.id] else {
            throw .policyDenied("commandAdmissionStale")
        }
        guard entry.uid == uid else { throw .unauthorized }
        guard entry.bootID == bootID, entry.generation == generation else {
            throw .policyDenied("commandAdmissionStale")
        }
        guard receipt.sequence == entry.sequence,
              receipt.expiresAtMonotonic == entry.expiresAtMonotonic else {
            throw .policyDenied("commandAdmissionStale")
        }
        guard now.isFinite, now >= 0, now < entry.expiresAtMonotonic else {
            entries.removeValue(forKey: receipt.id)
            throw .policyDenied("commandAdmissionStale")
        }
        entries.removeValue(forKey: receipt.id)
    }

    public mutating func expire(now: Double) {
        guard now.isFinite, now >= 0 else {
            entries.removeAll()
            return
        }
        entries = entries.filter { now < $0.value.expiresAtMonotonic }
    }

    /// Stop, safety, or owner loss invalidates every outstanding receipt.
    public mutating func revokeAll() {
        entries.removeAll()
    }
}
