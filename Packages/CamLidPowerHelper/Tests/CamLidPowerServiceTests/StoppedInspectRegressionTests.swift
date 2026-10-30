import Foundation
import Testing
import LidRecoveryJournal
@testable import CamLidPowerService

private final class StoppedInspectStore: PowerIntentStore {
    var commits = 0
    func load() throws -> JournalEntry? { nil }
    func commit(_ entry: JournalEntry, replacing revision: UInt64?) throws { commits += 1 }
}

private final class StoppedInspectMechanism: LeasePowerMechanism {
    let family = "lid-specific-v1"
    let maximumSessionSeconds = 60
    let applyAcknowledged = false
    var calls = 0
    func admissionAllowed() throws -> Bool { calls += 1; return true }
    func apply(remainingNanos: UInt64, episodeID: UUID) throws { calls += 1 }
    func readApplied() throws -> Bool? { calls += 1; return nil }
    func readForeignPolicy() throws -> ForeignPolicyObservation { calls += 1; return .clear }
    func clear() throws -> CleanupEvidence { calls += 1; return .callsAcknowledgedOnly }
}

@Test func idleSleepEventMakesInspectAcceptedButStoppedUntilNewServiceInstance() {
    let store = StoppedInspectStore(), mechanism = StoppedInspectMechanism(), owner = UUID()
    func makeService() -> PowerLeaseService {
        PowerLeaseService(mechanism: mechanism, store: store, bootID: "synthetic-boot",
                          clock: { 100 }, safety: {
            HelperSafety(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501,
                         lidClosed: false, externalDisplays: 0)
        })
    }
    let service = makeService()
    service.start()
    let ready = service.handle(PowerRequest(operation: .inspect), owner: owner, uid: 501)
    #expect(ready.accepted && ready.state == "ready" && ready.reason == "noPendingIntent")
    service.observeSystemEvent(reason: "sleepObserved")
    service.observeSystemEvent(reason: "anotherEvent")
    service.start() // Existing instance must not be rearmed by start or repeated Inspect.
    for _ in 0..<2 {
        let stopped = service.handle(PowerRequest(operation: .inspect), owner: owner, uid: 501)
        #expect(stopped.accepted && stopped.state == "stopped" && stopped.reason == "sleepObserved")
        #expect(!stopped.mutationAttempted && stopped.token == nil)
        #expect(stopped.leaseRemainingSeconds == nil && stopped.sessionRemainingSeconds == nil)
    }
    let refused = service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 60), owner: owner, uid: 501)
    #expect(!refused.accepted && refused.reason == "notReady")
    service.shutdown()
    #expect(mechanism.calls == 0 && store.commits == 0)
    let newService = makeService()
    newService.start()
    let fresh = newService.handle(PowerRequest(operation: .inspect), owner: owner, uid: 501)
    #expect(fresh.accepted && fresh.state == "ready" && fresh.reason == "noPendingIntent")
    #expect(mechanism.calls == 0 && store.commits == 0)
    #expect(!fresh.qualifiedClosedLidProtection)
}
