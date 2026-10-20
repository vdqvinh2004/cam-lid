import Foundation
import Testing
@testable import CamLidCore

struct EventIntegerBoundsTests {
    @Test func slashSeparatedIdentitiesHaveDistinctTaskIDs() throws {
        var normalizer = EvidenceNormalizer()
        for (session, run) in [("a/b", "c"), ("a", "b/c")] {
            _ = normalizer.normalize(try NormalizedEvent(provider: "codex", sessionID: session, runID: run,
                state: .working, evidenceKind: .lifecycle, confidence: .exact, sequence: 0, receivedMonotonic: 1))
        }
        #expect(normalizer.allTasks.count == 2)
        #expect(Set(normalizer.allTasks.map(\.id)).count == 2)
        #expect(normalizer.allTasks.allSatisfy { $0.id.hasPrefix("evt-") })
    }

    @Test func unknownAfterConfirmedIdleCannotHoldEarlierCompletedWork() throws {
        var normalizer = EvidenceNormalizer()
        for (sequence, state) in [TaskState.working, .idle, .unknown].enumerated() {
            _ = normalizer.normalize(try NormalizedEvent(provider: "codex", sessionID: "s", runID: "r",
                state: state, evidenceKind: .lifecycle, confidence: .exact, sequence: sequence, receivedMonotonic: Double(sequence)))
        }
        let task = try #require(normalizer.allTasks.first)
        #expect(task.state == .unknown && task.unknownUntilMonotonic == nil)
        #expect(!PolicyEngine.holdsSession(task, now: 3))
    }
    @Test func controlCharactersCannotCollideNormalizedIdentityTuples() throws {
        for identity in ["a\0b", "a\nb", "a\tb"] {
            #expect(throws: ValidationError.invalidIDCharacters) { try validateID(identity) }
            let object: [String: Any] = ["provider": "codex", "sessionID": identity, "runID": "r",
                "state": "working", "evidenceKind": "lifecycle", "confidence": "exact",
                "sequence": 0, "receivedMonotonic": 1]
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(NormalizedEvent.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
        try validateID("phiên-作業")
    }
    @Test func invalidChildRowCannotCreateParentWorkingEvidence() {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "http://127.0.0.1:4096")
        let result = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: [
            OpenCodeSessionRow(sessionID: "parent", status: "idle", childSessionIDs: ["bad-child"], sequence: 0),
            OpenCodeSessionRow(sessionID: "bad-child", status: "busy", parentSessionID: "parent", sequence: Int.max)
        ]), takenMonotonic: 1, receivedMonotonic: 1, nowMonotonic: 1)
        #expect(result.events.first { $0.sessionID == "parent" }?.state == .idle)
        #expect(result.events.allSatisfy { $0.state != .working })
        #expect(result.notes.contains("invalidSnapshotIdentityOrSequence"))
    }
    @Test func maximumCountersRejectBeforeIncrementing() throws {
        for counter in ["sequence", "epoch"] {
            let object: [String: Any] = ["provider": "codex", "sessionID": "s", "runID": "r",
                "state": "working", "evidenceKind": "lifecycle", "confidence": "exact",
                "sequence": counter == "sequence" ? Int.max : 0,
                "epoch": counter == "epoch" ? Int.max : 0, "receivedMonotonic": 1]
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(NormalizedEvent.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
    }

    @Test func invalidSnapshotCounterDoesNotCrashOrSuppressNextValidRow() {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "http://127.0.0.1:4096")
        let invalid = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: [
            OpenCodeSessionRow(sessionID: "s", status: "busy", sequence: Int.max)
        ]), takenMonotonic: 1, receivedMonotonic: 1, nowMonotonic: 1)
        #expect(invalid.events.isEmpty)
        #expect(invalid.notes.contains("invalidSnapshotIdentityOrSequence"))
        let valid = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: [
            OpenCodeSessionRow(sessionID: "s", status: "busy", sequence: 0)
        ]), takenMonotonic: 2, receivedMonotonic: 2, nowMonotonic: 2)
        #expect(valid.events.count == 1 && valid.events.first?.state == .working)
        #expect(valid.events.first?.sequence == 0)
    }
    @Test func snapshotCountersNormalizeContiguouslyRejectRegressionAndResetOnReconnect() throws {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "http://127.0.0.1:4096")
        var store = RuntimeAgentStore()
        func snapshot(_ status: String, _ sequence: Int) -> OpenCodeSnapshot {
            OpenCodeSnapshot(sessions: [OpenCodeSessionRow(sessionID: "s", status: status, sequence: sequence)])
        }
        let first = adapter.reconcile(snapshot: snapshot("busy", 100), takenMonotonic: 1, receivedMonotonic: 1, nowMonotonic: 1)
        #expect(first.events.first?.sequence == 0)
        #expect(try store.ingest(JSONEncoder().encode(#require(first.events.first)), now: 1) == "applied")
        let next = adapter.reconcile(snapshot: snapshot("idle", 200), takenMonotonic: 2, receivedMonotonic: 2, nowMonotonic: 2)
        #expect(next.events.first?.sequence == 1)
        #expect(try store.ingest(JSONEncoder().encode(#require(next.events.first)), now: 2) == "applied")
        let stale = adapter.reconcile(snapshot: snapshot("busy", 150), takenMonotonic: 3, receivedMonotonic: 3, nowMonotonic: 3)
        #expect(stale.events.isEmpty && stale.notes == ["snapshotSequenceRegressed"])
        adapter.noteReconnect(sessionID: "s")
        let restarted = adapter.reconcile(snapshot: snapshot("idle", 1), takenMonotonic: 4, receivedMonotonic: 4, nowMonotonic: 4)
        #expect(restarted.events.first?.sequence == 0 && restarted.events.first?.epoch == 1)
        #expect(try store.ingest(JSONEncoder().encode(#require(restarted.events.first)), now: 4) == "applied")
        #expect(store.tasks(now: 4).first?.state == .idle)
    }

    @Test func adapterCapacityRejectsNewMetadataWithoutEvictingExistingWork() throws {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "http://127.0.0.1:4096")
        for index in 0..<64 {
            guard case .event = adapter.parse(OpenCodeEventPayload(type: "busy", sessionID: "s-\(index)"), receivedMonotonic: 1) else {
                Issue.record("Expected admitted identity"); return
            }
        }
        guard case .ignored = adapter.parse(OpenCodeEventPayload(type: "busy", sessionID: "overflow"), receivedMonotonic: 2) else {
            Issue.record("Overflow was admitted"); return
        }
        let overflow = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: [OpenCodeSessionRow(sessionID: "overflow", status: "busy")]), takenMonotonic: 2, receivedMonotonic: 2, nowMonotonic: 2)
        #expect(overflow.events.isEmpty && overflow.notes == ["adapterCapacityFull"])
        guard case let .event(retained) = adapter.parse(OpenCodeEventPayload(type: "idle", sessionID: "s-0"), receivedMonotonic: 3) else {
            Issue.record("Existing identity was evicted"); return
        }
        #expect(retained.sequence == 1 && retained.state == .idle)
        adapter.forgetSession("s-63")
        guard case let .event(fresh) = adapter.parse(OpenCodeEventPayload(type: "busy", sessionID: "overflow"), receivedMonotonic: 4) else {
            Issue.record("Explicit cleanup did not release capacity"); return
        }
        #expect(fresh.sequence == 0)
    }

    @Test func rejectedMissingSnapshotRetainsStateForAValidUnknownRetry() {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "stdin")
        let initial = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: [
            OpenCodeSessionRow(sessionID: "parent", status: "idle", childSessionIDs: ["child"]),
            OpenCodeSessionRow(sessionID: "child", status: "busy", parentSessionID: "parent")
        ]), takenMonotonic: 1, receivedMonotonic: 1, nowMonotonic: 1)
        #expect(initial.events.count == 2 && initial.events.allSatisfy { $0.state == .working })
        let rejected = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: []), takenMonotonic: 2, receivedMonotonic: .nan, nowMonotonic: 2)
        #expect(rejected.events.isEmpty && rejected.notes.contains("invalidSnapshotIdentityOrSequence"))
        let retried = adapter.reconcile(snapshot: OpenCodeSnapshot(sessions: []), takenMonotonic: 3, receivedMonotonic: 3, nowMonotonic: 3)
        #expect(retried.events.count == 2 && retried.events.allSatisfy { $0.state == .unknown && $0.sequence == 1 })
        #expect(Set(retried.events.map(\.sessionID)) == ["parent", "child"])
    }

    @Test func openCodeChildCapacityRejectsWithoutChangingRetainedParentEvidence() throws {
        var adapter = OpenCodeAdapter(optIn: true, endpoint: "stdin")
        for index in 0..<63 {
            guard case .event = adapter.parse(OpenCodeEventPayload(type: "busy", sessionID: "s-\(index)"), receivedMonotonic: 1) else {
                Issue.record("Expected admitted identity"); return
            }
        }
        let overflow = adapter.parse(OpenCodeEventPayload(type: "child.start", sessionID: "new-parent", childSessionID: "new-child"), receivedMonotonic: 2)
        #expect(overflow == .ignored(reason: "adapterCapacityFull"))
        let admitted = adapter.parse(OpenCodeEventPayload(type: "child.start", sessionID: "s-0", childSessionID: "new-child"), receivedMonotonic: 3)
        guard case let .event(child) = admitted else { Issue.record("Rejected overflow consumed capacity"); return }
        #expect(child.sequence == 0 && child.parentRunID == "s-0")
        let rejected = adapter.parse(OpenCodeEventPayload(type: "child.start", sessionID: "s-0", childSessionID: "overflow-child"), receivedMonotonic: 4)
        #expect(rejected == .ignored(reason: "adapterCapacityFull"))
        let settled = adapter.parse(OpenCodeEventPayload(type: "idle", sessionID: "s-0"), receivedMonotonic: 5)
        guard case let .event(parent) = settled else { Issue.record("Parent was evicted"); return }
        #expect(parent.sequence == 1 && parent.state == .idle)
    }

}
