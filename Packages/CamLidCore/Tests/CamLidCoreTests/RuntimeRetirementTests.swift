import Foundation
import Testing
@testable import CamLidCore

@Suite("Runtime run retirement")
struct RuntimeRetirementTests {
    private func event(
        _ runID: String,
        _ sequence: Int,
        state: TaskState = .working,
        provider: String = "codex",
        sessionID: String = "session",
        epoch: Int = 0
    ) throws -> Data {
        try JSONEncoder().encode(NormalizedEvent(
            provider: provider,
            sessionID: sessionID,
            runID: runID,
            state: state,
            evidenceKind: .lifecycle,
            confidence: .exact,
            sequence: sequence,
            epoch: epoch,
            receivedMonotonic: 99_999
        ))
    }

    @Test func expiredUnknownWorkingAndWaitingRowsFreeEnrollmentSlots() throws {
        var store = RuntimeAgentStore()
        var received = 0.0

        for index in 0..<20 {
            let runID = "old-\(index)"
            switch index {
            case 0..<6:
                _ = try store.ingest(event(runID, 0), now: received)
            case 6..<12:
                _ = try store.ingest(event(runID, 0), now: received)
                _ = try store.ingest(event(runID, 1, state: .unknown), now: received + 0.1)
            case 12..<19:
                _ = try store.ingest(event(runID, 0), now: received)
                _ = try store.ingest(event(runID, 1, state: .waiting), now: received + 0.1)
            default:
                // Unknown without prior working is nonholding from inception.
                _ = try store.ingest(event(runID, 0, state: .unknown), now: received)
            }
            received += 1
        }

        #expect(store.tasks(now: received).count == 20)
        #expect(try store.ingest(event("fresh", 0), now: 1_000) == "applied")
        #expect(store.tasks(now: 1_000).map(\.runID) == ["fresh"])
    }

    @Test func twentyHoldingRunsRejectTwentyFirstWithoutChangingRows() throws {
        var store = RuntimeAgentStore()
        for index in 0..<20 {
            _ = try store.ingest(event("active-\(index)", 0), now: Double(index))
        }

        let before = store.tasks(now: 21)
        #expect(before.filter { PolicyEngine.holdsSession($0, now: 21) }.count == 20)
        #expect(throws: (any Error).self) {
            try store.ingest(event("overflow", 0), now: 21)
        }
        #expect(store.tasks(now: 21) == before)
        #expect(store.lastRejection == "enrollmentFull")
    }

    @Test func cachedIdleIdentityCannotBypassHoldingCapacity() throws {
        var store = RuntimeAgentStore()
        _ = try store.ingest(event("cached", 0, state: .idle), now: 0)
        for index in 0..<20 { _ = try store.ingest(event("active-\(index)", 0), now: 1) }
        #expect(throws: IPCError.policyDenied("enrollmentFull")) { try store.ingest(event("cached", 1), now: 2) }
        #expect(store.tasks(now: 2).first { $0.runID == "cached" }?.state == .idle)
        #expect(store.tasks(now: 2).filter { PolicyEngine.holdsSession($0, now: 2) }.count == 20)
    }

    @Test func gapFillCannotBypassHoldingCapacity() throws {
        var store = RuntimeAgentStore()
        #expect(try store.ingest(event("buffered", 1), now: 0) == "buffered")
        for index in 0..<20 { _ = try store.ingest(event("active-\(index)", 0), now: 1) }
        #expect(throws: IPCError.policyDenied("enrollmentFull")) {
            try store.ingest(event("buffered", 0, state: .idle), now: 2)
        }
        #expect(!store.tasks(now: 2).contains { $0.runID == "buffered" })
    }

    @Test func newerTerminalObservationCanClosePreviouslyRetiredStaleRun() throws {
        var store = RuntimeAgentStore()
        _ = try store.ingest(event("stale", 0), now: 0)
        _ = try store.ingest(event("fresh", 0), now: 200)
        #expect(store.retiredRunCount == 1)
        #expect(try store.ingest(event("stale", 1, state: .completed), now: 201) == "applied")
        #expect(store.tasks(now: 201).first { $0.runID == "stale" }?.state == .completed)
        #expect(throws: (any Error).self) { try store.ingest(event("stale", 2), now: 202) }
    }

    @Test func expiredReplayIsRejectedButNewerWorkingSequenceResumes() throws {
        var store = RuntimeAgentStore()
        _ = try store.ingest(event("same-run", 0), now: 10)

        #expect(throws: (any Error).self) {
            try store.ingest(event("same-run", 0), now: 146)
        }
        #expect(store.tasks(now: 146).isEmpty)
        #expect(throws: (any Error).self) {
            try store.ingest(event("same-run", 0), now: 147)
        }

        #expect(try store.ingest(event("same-run", 1), now: 148) == "applied")
        #expect(store.tasks(now: 148).first?.state == .working)
    }

    @Test func removingProviderClearsBufferedOnlyRuns() throws {
        var store = RuntimeAgentStore()
        #expect(try store.ingest(event("buffered", 1), now: 1) == "buffered")
        _ = try store.ingest(event("other-provider", 0, provider: "orca"), now: 1)

        store.remove(provider: "codex")
        #expect(store.tasks(provider: "codex", now: 2).isEmpty)
        #expect(store.tasks(provider: "orca", now: 2).count == 1)

        #expect(try store.ingest(event("buffered", 0, state: .idle), now: 2) == "applied")
        #expect(store.tasks(provider: "codex", now: 2).first?.state == .idle)
    }

    @Test func idleRowsRetireOnlyWhenNormalizerTableIsFull() throws {
        var store = RuntimeAgentStore()
        for index in 0..<64 {
            _ = try store.ingest(event("idle-\(index)", 0, state: .idle), now: Double(index))
        }

        #expect(try store.ingest(event("new-active", 0), now: 64) == "applied")
        #expect(store.tasks(now: 64).count == 64)
        #expect(!store.tasks(now: 64).contains { $0.runID == "idle-0" })
        #expect(store.tasks(now: 64).first { $0.runID == "new-active" }?.state == .working)
    }
    @Test func tablePressurePreservesIdleRunWithBufferedWorkingEvidence() throws {
        var store = RuntimeAgentStore()
        _ = try store.ingest(event("buffered", 0, state: .idle), now: 0)
        #expect(try store.ingest(event("buffered", 2), now: 1) == "buffered")
        for index in 0..<63 {
            _ = try store.ingest(event("idle-\(index)", 0, state: .idle), now: 2)
        }
        #expect(try store.ingest(event("fresh", 0), now: 3) == "applied")
        #expect(store.tasks(now: 3).contains { $0.runID == "buffered" })
        #expect(try store.ingest(event("buffered", 1, state: .idle), now: 4) == "applied")
        #expect(store.tasks(now: 4).first { $0.runID == "buffered" }?.state == .working)
    }

}
