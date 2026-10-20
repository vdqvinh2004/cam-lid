import Foundation

/// Owned-state recovery journal (Core value semantics; durable authenticated
/// persistence arrives with the helper). Committed before any global mutation;
/// corrupt/missing journal prevents mutation, uncertain recovery is never guessed.
/// T019 (Core half): corruption/full/read-only/crash/conflict/stalled/invalidation.
public enum JournalError: Error, Equatable, Sendable {
    case missing(String)
    case corrupt(String)
    case full(limit: Int)
    case readOnly
    case conflict(String)
    case unsupportedProtocol(have: Int, want: Int)
    case invalidRecord(String)
}

public enum RecoveryOutcome: String, Sendable, Codable, CaseIterable {
    case restorable, conflict, unknown, error
}

public struct RecoveryRecord: Sendable, Codable, Equatable {
    public var journalRevision: Int
    public var sessionID: String
    public var ownerIdentity: String
    public var protocolVersion: Int
    public var originalState: [String: String]
    public var expectedState: [String: String]
    public var restoreOutcome: RestoreState
    public var checksum: UInt64

    public init(
        journalRevision: Int, sessionID: String, ownerIdentity: String,
        protocolVersion: Int = 1, originalState: [String: String],
        expectedState: [String: String]
    ) throws(JournalError) {
        guard !sessionID.isEmpty else { throw .invalidRecord("empty sessionID") }
        guard !ownerIdentity.isEmpty else { throw .invalidRecord("empty ownerIdentity") }
        self.journalRevision = journalRevision
        self.sessionID = sessionID
        self.ownerIdentity = ownerIdentity
        self.protocolVersion = protocolVersion
        self.originalState = originalState
        self.expectedState = expectedState
        self.restoreOutcome = .pending
        self.checksum = 0
        self.checksum = Self.checksumOf(Self.canonicalForm(
            revision: journalRevision, session: sessionID, owner: ownerIdentity,
            proto: protocolVersion, original: originalState, expected: expectedState
        ))
    }

    public func verifyIntegrity() throws(JournalError) {
        let recomputed = Self.checksumOf(Self.canonicalForm(
            revision: journalRevision, session: sessionID, owner: ownerIdentity,
            proto: protocolVersion, original: originalState, expected: expectedState
        ))
        guard recomputed == checksum else { throw JournalError.corrupt(sessionID) }
    }

    private static func canonicalForm(
        revision: Int, session: String, owner: String, proto: Int,
        original: [String: String], expected: [String: String]
    ) -> String {
        let flat: ([String: String]) -> String = { dict in
            dict.keys.sorted().map { "\($0)=\(dict[$0]!)" }.joined(separator: ";")
        }
        return "\(revision)|\(session)|\(owner)|\(proto)|\(flat(original))|\(flat(expected))"
    }

    private static func checksumOf(_ string: String) -> UInt64 {
        // FNV-1a 64: tamper evidence, not a security boundary.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

public struct RecoveryJournal: Sendable {
    public let capacity: Int
    public var writable: Bool
    public let currentProtocol: Int
    private var records: [String: RecoveryRecord] = [:]
    private var order: [String] = []

    public init(capacity: Int = 64, writable: Bool = true, currentProtocol: Int = 1) {
        self.capacity = capacity
        self.writable = writable
        self.currentProtocol = currentProtocol
    }

    public var count: Int { records.count }

    public mutating func commit(_ record: RecoveryRecord) throws(JournalError) {
        guard writable else { throw .readOnly }
        guard record.protocolVersion == currentProtocol else {
            throw .unsupportedProtocol(have: record.protocolVersion, want: currentProtocol)
        }
        try record.verifyIntegrity()
        if records[record.sessionID] == nil, records.count >= capacity {
            throw JournalError.full(limit: capacity)
        }
        records[record.sessionID] = record
        if !order.contains(record.sessionID) { order.append(record.sessionID) }
    }

    public func record(for sessionID: String) throws(JournalError) -> RecoveryRecord {
        guard let record = records[sessionID] else { throw JournalError.missing(sessionID) }
        try record.verifyIntegrity()
        return record
    }

    public mutating func markRestore(sessionID: String, outcome: RestoreState) throws(JournalError) {
        var record = try record(for: sessionID)
        record.restoreOutcome = outcome
        records[sessionID] = record
    }

    /// Authenticated owned-state recovery. Uncertain ownership returns conflict or
    /// unknown with evidence; it never performs a guessed reset.
    public func recoverOwnedState(
        sessionID: String, requester: String, dryRun: Bool
    ) -> (outcome: RecoveryOutcome, evidence: [String: String]) {
        guard let record = try? record(for: sessionID) else {
            return (.unknown, ["reason": "journalMissing"])
        }
        guard record.ownerIdentity == requester else {
            return (.conflict, ["reason": "ownerMismatch", "session": sessionID])
        }
        guard !dryRun else {
            return (.restorable, ["reason": "dryRun", "expected": record.expectedState.keys.sorted().joined(separator: ",")])
        }
        if record.restoreOutcome == .verified {
            return (.restorable, ["reason": "alreadyVerified"])
        }
        return (.restorable, ["reason": "ownedRestore", "session": sessionID])
    }
}
