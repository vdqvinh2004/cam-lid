import Foundation

/// Append-only transition history (specs/005-native-ux T007, FR-016).
///
/// Privacy by construction: `StoredTransition` carries only state/revision/
/// reason/health-summary metadata. There are deliberately NO prompt, terminal,
/// code, secret, transcript, or path fields, so raw agent content can never
/// enter the store. Exports additionally pseudonymize session IDs and carry
/// only provider *kind* (raw host/path detail is never persisted).
///
/// Retention: 14 days OR 20 MiB, whichever is reached first; oldest records
/// are pruned first. Persistence section: docs/planning/domain-model.md.
///
/// Owned CLI history integration point: until `camlid logs` / `history`
/// commands are wired to this store, the CLI surfaces
/// `ActivityStore.historyUnavailableReason` instead of inventing history.
public struct StoredTransition: Sendable, Codable, Equatable {
    /// Schema version of this record. Bump on any field change.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let sessionID: String?
    public let timestamp: Date
    public let stateRevision: Int
    public let category: ActivityCategory
    public let previousState: EffectiveState?
    public let newState: EffectiveState
    public let reasonCodes: [String]
    /// Integration kind only (e.g. "opencode"). Never a hostname, path, or secret.
    public let providerKind: String?
    public let healthSummary: HealthSummary
    /// Present on session-ending transitions; preserved through export/delete filters.
    public let cleanupOutcome: CleanupOutcome?

    public init(
        id: UUID = UUID(),
        sessionID: String? = nil,
        timestamp: Date = Date(),
        stateRevision: Int,
        category: ActivityCategory,
        previousState: EffectiveState? = nil,
        newState: EffectiveState,
        reasonCodes: [String] = [],
        providerKind: String? = nil,
        healthSummary: HealthSummary = .unknown,
        cleanupOutcome: CleanupOutcome? = nil
    ) throws(ValidationError) {
        if let sessionID { try validateID(sessionID) }
        for code in reasonCodes { try validateString(code) }
        if let providerKind { try validateString(providerKind) }
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.stateRevision = stateRevision
        self.category = category
        self.previousState = previousState
        self.newState = newState
        self.reasonCodes = reasonCodes
        self.providerKind = providerKind
        self.healthSummary = healthSummary
        self.cleanupOutcome = cleanupOutcome
    }

    /// Approximate persisted size, used for the 20 MiB rotation bound.
    public func estimatedSize() -> Int {
        (try? JSONEncoder().encode(self).count) ?? PolicyLimits.maxEventBytes
    }
}

/// Transition categories. Stable raw values; treat as machine codes.
public enum ActivityCategory: String, Sendable, Codable, CaseIterable {
    case stateTransition
    case safetyStop
    case grace
    case capExpiry
    case recovery
    case enrollment
    case configuration
}

/// Session-end cleanup result. Mirrors the lease restoreOutcome vocabulary
/// (verified only on verified restore; expiry alone never verifies).
public enum CleanupOutcome: String, Sendable, Codable, CaseIterable {
    case pending
    case verified
    case failed
    case conflict
    case unknown
}

/// Render-ready health digest. `nil` means unknown and MUST be rendered as
/// "Unknown" (never green, never zero) per design-system/camlid/MASTER.md.
public struct HealthSummary: Sendable, Codable, Equatable {
    public let battery: String?
    public let thermal: String?
    public let lidDisplay: String?
    public let temperature: TemperatureObservation?
    public let lidObservation: LidObservation?

    public static let unknown = HealthSummary(battery: nil, thermal: nil, lidDisplay: nil)

    public init(battery: String? = nil, thermal: String? = nil, lidDisplay: String? = nil,
                temperature: TemperatureObservation? = nil, lidObservation: LidObservation? = nil) {
        self.battery = battery
        self.thermal = thermal
        self.lidDisplay = lidDisplay
        self.temperature = temperature; self.lidObservation = lidObservation
    }

    /// Builds a summary from a Core snapshot. Unknown measurements stay `nil`;
    /// capability verification is surfaced as text, never implied.
    public static func from(_ snapshot: HealthSnapshot) -> HealthSummary {
        let battery: String? = snapshot.batteryPercent.map { "\(Int($0))% · \(snapshot.powerSource.rawValue)" }
        let thermal: String? = snapshot.thermalPressure == .unknown ? nil : snapshot.thermalPressure.rawValue
        let lidDisplay: String?
        if snapshot.lidState == .unknown && snapshot.internalDisplayState == .unknown {
            lidDisplay = nil
        } else {
            let verified = snapshot.capabilityVerified ? " [verified]" : " [unverified]"
            lidDisplay = "Lid \(snapshot.lidState.rawValue) · Display \(snapshot.internalDisplayState.rawValue)" + verified
        }
        return HealthSummary(battery: battery, thermal: thermal, lidDisplay: lidDisplay,
            temperature: snapshot.temperature, lidObservation: snapshot.lid)
    }
}

/// Redacted export record. Session IDs are replaced by a salted stable
/// pseudonym; provider info carries kind only. No raw identifiers survive.
public struct RedactedTransition: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let id: UUID
    public let sessionPseudonym: String?
    public let timestamp: Date
    public let stateRevision: Int
    public let category: ActivityCategory
    public let previousState: EffectiveState?
    public let newState: EffectiveState
    public let reasonCodes: [String]
    public let providerKind: String?
    public let healthSummary: HealthSummary
    public let cleanupOutcome: CleanupOutcome?
}

/// Receipt for a delete operation. Returned to the caller (CLI/app), NOT
/// appended to queryable history: appending a marker containing the session
/// ID would defeat the deletion. The receipt itself is the tombstone.
public struct DeletionReceipt: Sendable, Codable, Equatable {
    public enum Scope: String, Sendable, Codable {
        case session
        case all
    }

    public let id: UUID
    public let scope: Scope
    public let sessionID: String?
    public let removedCount: Int
    public let deletedAt: Date
}

/// Storage seam for transition history. Implementations MUST preserve
/// append-only semantics for live records; removal happens only through
/// retention pruning or explicit user delete.
public protocol HistoryStorage: Sendable {
    func append(_ record: StoredTransition)
    func load() -> [StoredTransition]
    /// Removes every record matching the predicate. Returns the removed count.
    @discardableResult
    func removeAll(where shouldRemove: @Sendable (StoredTransition) -> Bool) -> Int
    /// Clears all persisted bytes, including corrupt entries.
    @discardableResult func clear() -> Int
}

public extension HistoryStorage {
    @discardableResult func clear() -> Int { removeAll { _ in true } }
}

/// In-memory storage with byte accounting. Suitable for tests and as the
/// seam until a rotated-JSONL file backend lands (same protocol).
public final class InMemoryHistoryStorage: HistoryStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [StoredTransition] = []
    private var sizes: [UUID: Int] = [:]
    private var totalBytes: Int = 0

    public init() {}

    public func append(_ record: StoredTransition) {
        lock.lock(); defer { lock.unlock() }
        // Replace on duplicate ID keeps append-only order without double counting.
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            totalBytes -= sizes[record.id, default: 0]
            records[index] = record
        } else {
            records.append(record)
        }
        let size = record.estimatedSize()
        sizes[record.id] = size
        totalBytes += size
    }

    public func load() -> [StoredTransition] {
        lock.lock(); defer { lock.unlock() }
        return records
    }

    @discardableResult
    public func removeAll(where shouldRemove: @Sendable (StoredTransition) -> Bool) -> Int {
        lock.lock(); defer { lock.unlock() }
        let doomed = records.filter(shouldRemove)
        guard !doomed.isEmpty else { return 0 }
        let doomedIDs = Set(doomed.map(\.id))
        records.removeAll { doomedIDs.contains($0.id) }
        for id in doomedIDs {
            totalBytes -= sizes.removeValue(forKey: id) ?? 0
        }
        return doomed.count
    }

    /// O(1) running total of estimated encoded bytes currently held.
    public func storedByteCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return totalBytes
    }

    /// Day accounting helper: number of records older than the cutoff.
    public func count(olderThan cutoff: Date) -> Int {
        lock.lock(); defer { lock.unlock() }
        return records.filter { $0.timestamp < cutoff }.count
    }
}

/// Append-only transition history with bounded retention, redacted export,
/// and explicit delete receipts.
public struct ActivityStore: Sendable {
    /// 14 days, per docs/planning/domain-model.md persistence section.
    public static let defaultRetentionSeconds: Double = 14 * 24 * 3_600
    /// 20 MiB including rotated files, per domain-model.md.
    public static let defaultMaxBytes: Int = 20 * 1_024 * 1_024

    /// Owned CLI history integration point: CLI surfaces this machine code
    /// until `camlid logs`/`history` commands are wired to this store.
    public static let historyUnavailableReason = "historyNotWired"

    private let storage: any HistoryStorage
    private let now: @Sendable () -> Date
    private let retentionSeconds: Double
    private let maxBytes: Int

    public init(
        storage: any HistoryStorage = InMemoryHistoryStorage(),
        now: @Sendable @escaping () -> Date = Date.init,
        retentionSeconds: Double = defaultRetentionSeconds,
        maxBytes: Int = defaultMaxBytes
    ) {
        self.storage = storage
        self.now = now
        self.retentionSeconds = retentionSeconds
        self.maxBytes = maxBytes
    }

    /// Appends a transition, then enforces retention (oldest pruned first).
    public func record(_ transition: StoredTransition) {
        record([transition])
    }

    /// Appends an ordered batch, enforcing retention once after its writes.
    public func record(_ transitions: [StoredTransition]) {
        for transition in transitions { storage.append(transition) }
        enforceRetention(now: now())
    }

    /// Oldest-first snapshot, optionally filtered by session and/or reason code.
    public func transitions(
        sessionID: String? = nil,
        reasonCode: String? = nil,
        category: ActivityCategory? = nil
    ) -> [StoredTransition] {
        storage.load()
            .filter { record in sessionID.map { wanted in wanted == record.sessionID } ?? true }
            .filter { record in reasonCode.map { wanted in record.reasonCodes.contains(wanted) } ?? true }
            .filter { record in category.map { wanted in wanted == record.category } ?? true }
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Enforces the 14-day / 20 MiB bounds, oldest first.
    public func enforceRetention(now reference: Date? = nil) {
        let reference = reference ?? now()
        let cutoff = reference.addingTimeInterval(-retentionSeconds)
        let ordered = storage.load().sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard !ordered.isEmpty else { return }
        var doomed = Set<UUID>()
        var remaining = ordered.map { ($0, $0.estimatedSize()) }
        // Day cap first.
        for (record, _) in remaining where record.timestamp < cutoff {
            doomed.insert(record.id)
        }
        remaining.removeAll { doomed.contains($0.0.id) }
        // Byte cap: whichever bound is hit first wins, oldest pruned first.
        var total = remaining.reduce(0) { $0 + $1.1 }
        for (record, size) in remaining {
            guard total > maxBytes else { break }
            doomed.insert(record.id)
            total -= size
        }
        guard !doomed.isEmpty else { return }
        let doomedIDs = doomed
        _ = storage.removeAll { doomedIDs.contains($0.id) }
    }

    /// Redacted export: session IDs become salt-stable pseudonyms, provider
    /// info carries kind only. Same salt + same session ID always yields the
    /// same pseudonym within and across exports; different salts differ.
    public func exportRedacted(salt: String) -> [RedactedTransition] {
        transitions().map { record in
            RedactedTransition(
                schemaVersion: record.schemaVersion,
                id: record.id,
                sessionPseudonym: record.sessionID.map { Self.pseudonym(sessionID: $0, salt: salt) },
                timestamp: record.timestamp,
                stateRevision: record.stateRevision,
                category: record.category,
                previousState: record.previousState,
                newState: record.newState,
                reasonCodes: record.reasonCodes,
                providerKind: record.providerKind,
                healthSummary: record.healthSummary,
                cleanupOutcome: record.cleanupOutcome
            )
        }
    }

    /// JSON form of `exportRedacted(salt:)` for `camlid logs export --redacted`.
    public func exportRedactedJSON(salt: String) throws -> Data {
        try JSONEncoder().encode(exportRedacted(salt: salt))
    }

    /// Deletes one session's transitions. Returns a tombstone receipt; the
    /// receipt is returned, never appended to history.
    @discardableResult
    public func delete(sessionID: String) -> DeletionReceipt {
        let removed = storage.removeAll { $0.sessionID == sessionID }
        return DeletionReceipt(
            id: UUID(), scope: .session, sessionID: sessionID,
            removedCount: removed, deletedAt: now()
        )
    }

    /// Deletes all transitions. Returns a tombstone receipt.
    @discardableResult
    public func deleteAll() -> DeletionReceipt {
        let removed = storage.clear()
        return DeletionReceipt(
            id: UUID(), scope: .all, sessionID: nil,
            removedCount: removed, deletedAt: now()
        )
    }

    /// Stable salted pseudonym (FNV-1a 64, hex). Pure-Swift so Core stays
    /// dependency-free; determinism is the requirement, not cryptographic strength.
    static func pseudonym(sessionID: String, salt: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (salt + "\u{1F}" + sessionID).utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "session-" + String(format: "%016llx", hash)
    }
}
