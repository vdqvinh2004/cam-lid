import Foundation
import Testing
@testable import CamLidCore

struct ProcessIdentityTests {
    @Test func reusedPIDProducesDistinctUnknownRuns() throws {
        let first = try ProcessRecord(identity: ProcessIdentity(pid: 123, startTime: 10), executableName: "codex", lastSeenMonotonic: 100)
        let second = try ProcessRecord(identity: ProcessIdentity(pid: 123, startTime: 20), executableName: "codex", lastSeenMonotonic: 100)
        let pattern = CandidatePattern(executableContains: "codex", provider: "codex")
        let one = ProcessDiscovery(provider: InMemoryProcessList(records: [first]), patterns: [pattern]).normalizedEvents(sessionID: "test", receivedMonotonic: 100)
        let two = ProcessDiscovery(provider: InMemoryProcessList(records: [second]), patterns: [pattern]).normalizedEvents(sessionID: "test", receivedMonotonic: 100)
        #expect(one.first?.runID != two.first?.runID)
        #expect(one.first?.state == .unknown && two.first?.state == .unknown)
        #expect(!ProcessDiscovery.canArmAuto(kind: .process))
    }
    @Test func silentLifecycleExpiresHoldWithoutClaimingCompletion() throws {
        var stream = try ProviderStream(provider: "codex", streamID: "silent")
        var store = RuntimeAgentStore()
        for line in [#"{"type":"thread.started","thread_id":"test"}"#, #"{"type":"turn.started"}"#] {
            for event in try stream.consume(Data(line.utf8), now: 10) { _ = try store.ingest(JSONEncoder().encode(event), now: 10) }
        }
        #expect(store.tasks(now: 24).first?.state == .working)
        #expect(store.tasks(now: 26).first?.state == .unknown)
        let expired = try #require(store.tasks(now: 146).first)
        #expect(expired.state == .unknown && expired.unknownUntilMonotonic == 145)
    }
}
