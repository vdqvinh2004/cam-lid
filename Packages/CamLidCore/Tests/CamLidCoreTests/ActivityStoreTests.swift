import Foundation
import Testing

@testable import CamLidCore

private func makeTransition(
    sessionID: String? = "session-1",
    timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
    revision: Int = 1,
    category: ActivityCategory = .stateTransition,
    previous: EffectiveState? = .ready,
    new: EffectiveState = .protected,
    reasons: [String] = ["holdingTask", "armed"],
    providerKind: String? = "opencode",
    cleanup: CleanupOutcome? = nil
) throws -> StoredTransition {
    try StoredTransition(
        sessionID: sessionID, timestamp: timestamp, stateRevision: revision,
        category: category, previousState: previous, newState: new,
        reasonCodes: reasons, providerKind: providerKind,
        healthSummary: .unknown, cleanupOutcome: cleanup
    )
}

private func fieldLabels(of value: Any) -> [String] {
    Mirror(reflecting: value).children.compactMap { $0.label?.lowercased() }
}

/// Fixed clock so fixture timestamps (Nov 2023) are "now", not 14-day stale.
private let fixtureNow = Date(timeIntervalSince1970: 1_700_000_000)

private func makeStore(maxBytes: Int = ActivityStore.defaultMaxBytes) -> ActivityStore {
    ActivityStore(storage: InMemoryHistoryStorage(), now: { fixtureNow }, maxBytes: maxBytes)
}

@Suite("Activity history privacy, rotation, redaction (T009)")
struct ActivityStoreTests {
    @Test("stored records carry no transcript-capable fields by construction")
    func noTranscriptCapableFields() throws {
        let record = try makeTransition()
        let storedLabels = fieldLabels(of: record)
        for banned in ["prompt", "transcript", "secret", "password", "content"] {
            #expect(
                !storedLabels.contains { $0.contains(banned) },
                "StoredTransition field leaks \(banned): \(storedLabels)"
            )
        }
        // Allowlisted top-level keys only: nothing smuggled under another name.
        let data = try JSONEncoder().encode(record)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("stored record did not encode as a JSON object")
            return
        }
        let keys = Set(object.keys)
        let allowed: Set<String> = [
            "schemaVersion", "id", "sessionID", "timestamp", "stateRevision",
            "category", "previousState", "newState", "reasonCodes",
            "providerKind", "healthSummary", "cleanupOutcome",
        ]
        #expect(keys.isSubset(of: allowed), "unexpected keys: \(keys.subtracting(allowed))")
        // Health summary carries no free-text content channel either.
        let healthLabels = fieldLabels(of: record.healthSummary)
        for banned in ["prompt", "transcript", "secret", "password"] {
            #expect(!healthLabels.contains { $0.contains(banned) })
        }
    }

    @Test("day cap prunes records older than 14 days, oldest first")
    func dayCapPrunesOldest() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ActivityStore(storage: InMemoryHistoryStorage(), now: { now })
        let old = try makeTransition(sessionID: "old", timestamp: now.addingTimeInterval(-15 * 24 * 3_600))
        let fresh = try makeTransition(sessionID: "fresh", timestamp: now)
        store.record(old)
        store.record(fresh)
        // Recording `fresh` triggers enforcement; `old` must be gone.
        let remaining = store.transitions()
        #expect(remaining.map(\.sessionID) == ["fresh"])
    }

    @Test("byte cap prunes oldest first and keeps the newest")
    func byteCapPrunesOldest() throws {
        let store = makeStore(maxBytes: 400)
        var ids: [UUID] = []
        for index in 0..<6 {
            let record = try makeTransition(
                sessionID: "s-\(index)",
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
            ids.append(record.id)
            store.record(record)
        }
        let remaining = store.transitions()
        #expect(remaining.count < 6, "byte cap must prune")
        #expect(!remaining.map(\.id).contains(ids.first!), "oldest must be pruned first")
        #expect(remaining.map(\.id).contains(ids.last!), "newest must be retained")
        // Timestamps stay ordered oldest-first after pruning.
        #expect(remaining.map(\.timestamp) == remaining.map(\.timestamp).sorted())
    }

    @Test("redacted export pseudonyms are stable per salt, differ across salts, hide raw IDs")
    func redactionPseudonyms() throws {
        let sentinelSession = "SENTINEL-secret-session-9f3k"
        let store = makeStore()
        try store.record(makeTransition(sessionID: sentinelSession))
        try store.record(makeTransition(sessionID: "session-1"))
        try store.record(makeTransition(sessionID: sentinelSession, revision: 2, new: .completionGrace))

        let exportA = store.exportRedacted(salt: "salt-a")
        let exportA2 = store.exportRedacted(salt: "salt-a")
        let exportB = store.exportRedacted(salt: "salt-b")

        let pseudoA = exportA.compactMap(\.sessionPseudonym)
        // Stable within and across exports with the same salt.
        #expect(pseudoA.count == 3)
        #expect(exportA2.compactMap(\.sessionPseudonym) == pseudoA)
        // Two distinct sessions collapse to exactly two pseudonyms: the two
        // sentinel records share one, session-1 has the other.
        #expect(Set(pseudoA).count == 2)
        // Differ across salts.
        #expect(exportB.compactMap(\.sessionPseudonym) != pseudoA)
        for pseudo in pseudoA { #expect(!pseudo.contains("SENTINEL")) }

        // Raw IDs absent from the encoded export.
        let json = String(decoding: try store.exportRedactedJSON(salt: "salt-a"), as: UTF8.self)
        #expect(!json.contains(sentinelSession), "raw session ID leaked into export")
        #expect(!json.contains("session-1") || json.contains("session-"), "unexpected raw ID")
        // Provider kind (not host detail) survives redaction.
        #expect(json.contains("opencode"))
    }

    @Test("session and reason filters select; end reasons and cleanup outcomes survive")
    func filtersAndOutcomesPreserved() throws {
        let store = makeStore()
        try store.record(makeTransition(sessionID: "s-1", new: .expired, reasons: ["capReached"], cleanup: .verified))
        try store.record(makeTransition(sessionID: "s-1", revision: 2, new: .ready, reasons: ["graceExpired"], cleanup: .unknown))
        try store.record(makeTransition(sessionID: "s-2", new: .safetyStopped, reasons: ["thermalSerious"], cleanup: .failed))

        #expect(store.transitions(sessionID: "s-1").count == 2)
        #expect(store.transitions(reasonCode: "thermalSerious").map(\.sessionID) == ["s-2"])
        #expect(store.transitions(sessionID: "s-1", reasonCode: "capReached").count == 1)

        let expired = store.transitions(reasonCode: "capReached").first!
        #expect(expired.cleanupOutcome == .verified)
        #expect(expired.newState == .expired)
        let safety = store.transitions(reasonCode: "thermalSerious").first!
        #expect(safety.cleanupOutcome == .failed)

        // Outcomes also survive the redacted export path.
        let exported = store.exportRedacted(salt: "x")
        #expect(exported.first { $0.reasonCodes.contains("capReached") }?.cleanupOutcome == .verified)
        #expect(exported.first { $0.reasonCodes.contains("thermalSerious") }?.cleanupOutcome == .failed)
    }

    @Test("delete returns a tombstone receipt and removes only the target")
    func deleteReceipt() throws {
        let store = makeStore()
        try store.record(makeTransition(sessionID: "s-1"))
        try store.record(makeTransition(sessionID: "s-2"))
        let receipt = store.delete(sessionID: "s-1")
        #expect(receipt.scope == .session)
        #expect(receipt.removedCount == 1)
        #expect(store.transitions().map(\.sessionID) == ["s-2"])
        let all = store.deleteAll()
        #expect(all.scope == .all)
        #expect(all.removedCount == 1)
        #expect(store.transitions().isEmpty)
    }

    @Test("CLI surfaces a stable unavailable reason until history is wired")
    func historyUnavailableReason() {
        #expect(ActivityStore.historyUnavailableReason == "historyNotWired")
    }
}
