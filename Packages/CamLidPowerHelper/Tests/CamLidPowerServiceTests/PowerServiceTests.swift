import Foundation
import Testing
import LidRecoveryJournal
@testable import CamLidPowerService

private final class FakeBackend: SleepOverrideBackend {
    var disabled = false
    var writes: [Bool] = []
    var writeFails = false
    var readFails = false
    var afterWrite: (() -> Void)?
    func readDisabled() throws -> Bool {
        if readFails { throw PowerServiceFailure.backend }
        return disabled
    }
    func setDisabled(_ value: Bool) throws {
        writes.append(value)
        if writeFails { throw PowerServiceFailure.backend }
        disabled = value
        afterWrite?()
    }
}

private final class FakeStore: PowerIntentStore {
    var record: JournalEntry?
    var commits = 0
    var failAt: Int?
    var loadFails = false
    var afterCommit: (() -> Void)?
    func load() throws -> JournalEntry? {
        if loadFails { throw PowerServiceFailure.journal }
        return record
    }
    func commit(_ entry: JournalEntry, replacing revision: UInt64?) throws {
        commits += 1
        if failAt == commits { throw PowerServiceFailure.journal }
        guard record?.revision == revision else { throw PowerServiceFailure.journal }
        record = entry
        afterCommit?()
    }
}

private final class Fixture {
    let backend = FakeBackend()
    let store = FakeStore()
    let owner = UUID()
    var time = 100.0
    var safetyDelay = 0.0
    var safety =  HelperSafety(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501,
                              lidClosed: false, externalDisplays: 0)
    lazy var service = makeService()
    func makeService(bootID: String = "boot-a") -> PowerLeaseService {
        PowerLeaseService(backend: backend, store: store, bootID: bootID,
                          clock: { self.time }, safety: {
                              self.time += self.safetyDelay
                              return self.safety
                          })
    }
    func acquire(seconds: Int = 300) -> PowerReply {
        service.start()
        return service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: seconds),
                              owner: owner, uid: 501)
    }
}

@Suite struct PowerServiceTests {
    @Test func startsAndRestoresAfterStop() throws {
        let f = Fixture()
        let started = f.acquire()
        #expect(started.accepted && started.state == "active")
        #expect(started.qualifiedClosedLidProtection == false)
        #expect(f.store.record?.disposition == .acknowledged)
        let stopped = f.service.handle(PowerRequest(operation: .release, token: started.token), owner: f.owner, uid: 501)
        #expect(stopped.accepted && stopped.state == "restored")
        #expect(f.backend.writes == [true, false])
        #expect(f.store.record?.intent == .restoreLidPolicy)
    }

    @Test func heartbeatExpiryUsesContinuousDeadline() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.time = 130
        f.service.poll()
        #expect(f.backend.writes == [true, false])
        #expect(f.service.reason == "heartbeatExpired")
    }

    @Test func renewalCannotExtendSessionCapOrReviveExpiredLease() {
        let f = Fixture()
        let lease = f.acquire(seconds: 45)
        f.time = 120
        let renewed = f.service.handle(PowerRequest(operation: .renew, token: lease.token, sequence: 2), owner: f.owner, uid: 501)
        #expect(renewed.leaseRemainingSeconds == 25)
        f.time = 145
        let late = f.service.handle(PowerRequest(operation: .renew, token: lease.token, sequence: 3), owner: f.owner, uid: 501)
        #expect(!late.accepted)
        #expect(f.backend.writes == [true, false])
        #expect(f.service.reason == "sessionExpired")
    }

    @Test func staleOwnerTokenSequenceAndCrossUserRefused() {
        let f = Fixture()
        let lease = f.acquire()
        for (owner, uid, token, sequence) in [
            (UUID(), UInt32(501), lease.token, UInt64(2)),
            (f.owner, UInt32(502), lease.token, UInt64(2)),
            (f.owner, UInt32(501), UUID(), UInt64(2)),
            (f.owner, UInt32(501), lease.token, UInt64(1)),
        ] {
            #expect(!f.service.handle(PowerRequest(operation: .renew, token: token, sequence: sequence), owner: owner, uid: uid).accepted)
        }
        f.service.disconnected(owner: UUID())
        #expect(f.backend.writes == [true])
        f.service.disconnected(owner: f.owner)
        #expect(f.backend.writes == [true, false])
    }

    @Test func preexistingOverrideIsNeverAdoptedOrCleared() {
        let f = Fixture()
        f.backend.disabled = true
        #expect(f.acquire().reason == "preexistingOverride")
        f.service.shutdown()
        #expect(f.backend.writes.isEmpty)
        #expect(f.store.record == nil)
    }

    @Test func invalidRequestsAndUnsafeAdmissionNeverWrite() {
        for seconds in [0, -1, PowerLeaseService.maximumSessionSeconds + 1] {
            let f = Fixture()
            #expect(!f.acquire(seconds: seconds).accepted)
            #expect(f.backend.writes.isEmpty)
        }
        let readings: [HelperSafety] = [
            .init(onAC: false, batteryPercent: 80, thermalNominal: true, consoleUID: 501, lidClosed: false, externalDisplays: 0),
            .init(onAC: true, batteryPercent: nil, thermalNominal: true, consoleUID: 501, lidClosed: false, externalDisplays: 0),
            .init(onAC: true, batteryPercent: .nan, thermalNominal: true, consoleUID: 501, lidClosed: false, externalDisplays: 0),
            .init(onAC: true, batteryPercent: 19, thermalNominal: true, consoleUID: 501, lidClosed: false, externalDisplays: 0),
            .init(onAC: true, batteryPercent: 80, thermalNominal: false, consoleUID: 501, lidClosed: false, externalDisplays: 0),
            .init(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 502, lidClosed: false, externalDisplays: 0),
            .init(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501, lidClosed: nil, externalDisplays: 0),
            .init(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501, lidClosed: true, externalDisplays: 0),
            .init(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501, lidClosed: false, externalDisplays: 1),
        ]
        for reading in readings {
            let f = Fixture()
            f.safety = reading
            #expect(f.acquire().reason == "safetyRefused")
            #expect(f.backend.writes.isEmpty)
        }
    }

    @Test func closedLidCanContinueButACLossStops() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.safety = .init(onAC: true, batteryPercent: 80, thermalNominal: true, consoleUID: 501, lidClosed: true, externalDisplays: 0)
        f.service.poll()
        #expect(f.service.state == "active")
        f.safety = .init(onAC: false, batteryPercent: 80, thermalNominal: true, consoleUID: 501, lidClosed: true, externalDisplays: 0)
        f.service.poll()
        #expect(f.backend.writes == [true, false])
        #expect(f.service.reason == "safetyStop")
    }

    @Test func journalMustPrecedeEnableAndLateCommitCannotEnable() {
        let f = Fixture()
        f.store.failAt = 1
        #expect(!f.acquire().accepted)
        #expect(f.backend.writes.isEmpty)
        let slow = Fixture()
        slow.store.afterCommit = { slow.time = 131 }
        #expect(!slow.acquire().accepted)
        #expect(slow.backend.writes.isEmpty)
    }

    @Test func knownSuccessfulEnableRollsBackAfterAckFailure() {
        let f = Fixture()
        f.store.failAt = 2
        #expect(!f.acquire().accepted)
        #expect(f.backend.writes == [true, false])
        #expect(f.service.state == "restored")
    }

    @Test func failedEnableAndInterruptedRestoreRemainUncertainOnRestart() {
        let f = Fixture()
        f.backend.writeFails = true
        #expect(!f.acquire().accepted)
        #expect(f.store.record?.disposition == .pending)
        f.backend.writeFails = false
        f.backend.disabled = true
        let replacement = f.makeService()
        replacement.start()
        #expect(replacement.state == "recoveryRequired")
        #expect(f.backend.writes == [true])
    }

    @Test func acknowledgedEnableCanRestoreOnSameBootHelperRestart() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        let replacement = f.makeService()
        replacement.start()
        #expect(replacement.state == "restored")
        #expect(f.backend.writes == [true, false])
    }

    @Test func otherBootRestoresAcknowledgedOverrideForPersistentGlobalPolicy() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        let replacement = f.makeService(bootID: "boot-b")
        replacement.start()
        #expect(replacement.state == "restored")
        #expect(f.backend.disabled == false)
        #expect(f.backend.writes == [true, false])
    }

    @Test func otherBootNeverClearsAnUncertainEnable() {
        let f = Fixture()
        f.backend.writeFails = true
        #expect(!f.acquire().accepted)
        f.backend.writeFails = false
        f.backend.disabled = true
        let replacement = f.makeService(bootID: "boot-b")
        replacement.start()
        #expect(replacement.state == "recoveryRequired")
        #expect(f.backend.writes == [true])
    }

    @Test func otherBootWithPolicyAlreadyClearAcknowledgesWithoutWriting() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.backend.disabled = false
        let replacement = f.makeService(bootID: "boot-b")
        replacement.start()
        #expect(replacement.state == "restored")
        #expect(f.backend.writes == [true])
    }

    @Test func restartAfterLeaseExpiryRestoresBeforeAcceptingNewWork() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.time += 3600
        let replacement = f.makeService()
        replacement.start()
        #expect(replacement.state == "restored")
        #expect(f.backend.disabled == false)
    }

    @Test func restoreFailurePreventsNewProtection() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.backend.writeFails = true
        f.service.shutdown()
        #expect(f.service.state == "recoveryRequired")
        #expect(!f.acquire().accepted)
    }

    @Test func uncertainRestoreNeverDispatchesAgainOnDisconnectOrShutdown() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.backend.writeFails = true
        f.service.shutdown()
        f.service.disconnected(owner: f.owner)
        f.service.shutdown()
        #expect(f.backend.writes == [true, false])
        #expect(f.service.state == "recoveryRequired")
    }

    @Test func unsupportedProtocolStillEnforcesAnExpiredLease() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.time = 130
        var request = PowerRequest(operation: .inspect)
        request.version = 2
        let result = f.service.handle(request, owner: f.owner, uid: 501)
        #expect(!result.accepted && result.reason == "unsupportedProtocol")
        #expect(result.state == "restored")
        #expect(f.backend.writes == [true, false])
    }

    @Test func malformedPacketsStillEnforceAnExpiredLease() async {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.time = 130
        let runtime = PowerHelperRuntime(service: f.service)
        runtime.start()
        let response: Data = await withCheckedContinuation { continuation in
            runtime.perform(Data(repeating: 0, count: 5000), owner: f.owner, uid: 501) {
                continuation.resume(returning: $0)
            }
        }
        let result = try? JSONDecoder().decode(PowerReply.self, from: response)
        #expect(result?.accepted == false && result?.reason == "invalidRequest")
        #expect(result?.state == "restored" && result?.mutationAttempted == true)
        #expect(f.backend.writes == [true, false])
        await withCheckedContinuation { continuation in runtime.shutdown { continuation.resume() } }
    }

    @Test func clockRegressionTriggersRestoration() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.time = 99
        f.service.poll()
        #expect(f.backend.writes == [true, false])
        #expect(f.service.reason == "monitorFailed")
    }

    @Test func slowEnableIsRestoredRatherThanAcknowledgedActive() {
        let f = Fixture()
        f.backend.afterWrite = { f.time = 150 }
        #expect(!f.acquire().accepted)
        #expect(f.backend.writes == [true, false])
    }

    @Test func slowSafetyReadCannotAdmitOrExtendAHealthyLease() {
        let f = Fixture()
        f.safetyDelay = 1.1
        #expect(f.acquire().reason == "safetyRefused")
        #expect(f.backend.writes.isEmpty)
        let active = Fixture()
        #expect(active.acquire().accepted)
        active.time = 129.5
        active.safetyDelay = 1.1
        active.service.poll()
        #expect(active.backend.writes == [true, false])
        #expect(active.service.reason == "heartbeatExpired")
    }

    @Test func durableJournalReopensAndDrivesSameBootRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DurableRecoveryJournal(directory: directory)
        let f = Fixture()
        let original = PowerLeaseService(backend: f.backend, store: store, bootID: "boot-a",
            clock: { f.time }, safety: { f.safety })
        original.start()
        let lease = original.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 300), owner: f.owner, uid: 501)
        #expect(lease.accepted)
        let reopened = try DurableRecoveryJournal(directory: directory)
        let replacement = PowerLeaseService(backend: f.backend, store: reopened, bootID: "boot-a",
            clock: { f.time }, safety: { f.safety })
        replacement.start()
        #expect(replacement.state == "restored")
        #expect(try reopened.load()?.intent == .restoreLidPolicy)
        #expect(f.backend.writes == [true, false])
    }

    @Test func externalClearRevokesWithoutReasserting() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.backend.disabled = false
        f.service.poll()
        #expect(f.service.state == "restored")
        #expect(f.service.reason == "overrideChanged")
        #expect(f.backend.writes == [true])
    }

    @Test func sameValueForeignWriteRemainsIndistinguishable() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        // Counterexample: another writer sets the same bit. No ownership token exists.
        f.backend.disabled = true
        let replacement = f.makeService()
        replacement.start()
        #expect(f.backend.writes == [true, false])
        #expect(!f.backend.disabled)
        // This documents loss of indistinguishable foreign intent, NOT a safety pass.
    }

    @Test func helperFailureDoesNotManufactureOSExpiry() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.time = 500
        // No executing poller: underlying global override remains enabled.
        #expect(f.backend.disabled)
        #expect(f.store.record?.intent == .enableLidOverride)
        #expect(f.backend.writes == [true])
    }
}

@Suite struct PMSetBackendTests {
    @Test func parsesOnlyOneExplicitBinaryGlobalValue() throws {
        #expect(try !PMSetBackend.decodeDisabled(Data("System-wide power settings:\n SleepDisabled\t0\nCurrently in use:\n sleep 1\n".utf8)))
        #expect(try PMSetBackend.decodeDisabled(Data("SleepDisabled 1\n".utf8)))
        for text in ["", "SleepDisabled 2", "SleepDisabled 0 extra", "SleepDisabled 0\nSleepDisabled 1", "SleepDisabled\0 0"] {
            #expect(throws: PMSetFailure.self) { try PMSetBackend.decodeDisabled(Data(text.utf8)) }
        }
        #expect(throws: PMSetFailure.self) { try PMSetBackend.decodeDisabled(Data([0xff])) }
    }

    @Test func nativeAdapterAllowsOnlyFixedCommandsAndChecksExit() throws {
        var commands: [PMSetCommand] = []
        let backend = PMSetBackend { command in
            commands.append(command)
            return PMSetResult(status: 0, output: Data("SleepDisabled 0\n".utf8))
        }
        #expect(try !backend.readDisabled())
        try backend.setDisabled(true)
        try backend.setDisabled(false)
        #expect(commands == [.inspect, .enable, .disable])
        #expect(PMSetCommand.enable.arguments == ["-a", "disablesleep", "1"])
        #expect(PMSetCommand.disable.arguments == ["-a", "disablesleep", "0"])
        let failed = PMSetBackend { _ in PMSetResult(status: 1, output: Data()) }
        #expect(throws: PMSetFailure.exit(1)) { try failed.setDisabled(true) }
    }
}

@Suite struct HelperLaunchModeTests {
    @Test func acceptsOnlyOneExplicitKnownArgument() {
        #expect(HelperLaunchMode(arguments: ["--standard-v1"]) == .standard)
        #expect(HelperLaunchMode(arguments: ["--lid-specific-v1"]) == .lidSpecific)
        #expect(HelperLaunchMode(arguments: ["--lid-specific-best-effort-v1"]) == .bestEffortLid)
        #expect(HelperLaunchMode(arguments: ["--recover-v1"]) == .recovery)
    }

    @Test func refusesMissingUnknownOrExtraArguments() {
        #expect(HelperLaunchMode(arguments: []) == nil)
        #expect(HelperLaunchMode(arguments: ["--standard"]) == nil)
        #expect(HelperLaunchMode(arguments: ["--standard-v1", "--lid-specific-v1"]) == nil)
        #expect(HelperLaunchMode(arguments: ["--version"]) == nil)
    }
}

@Suite struct IndependentRecoveryTests {
    private func acquired() -> Fixture {
        let f = Fixture()
        #expect(f.acquire().accepted)   // lease deadline = 100 + 30
        return f
    }

    @Test func doesNothingWhileTheLeaseIsValidOrWithinGrace() {
        let f = acquired()
        f.time = 120
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .leaseStillValid)
        f.time = 139
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .leaseStillValid)
        #expect(f.backend.disabled && f.backend.writes == [true])
    }

    @Test func restoresAfterDeadlinePlusGraceWhileTheHelperIsHung() {
        let f = acquired()
        f.time = 141   // the hung helper never polls; another process recovers
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .restored)
        #expect(!f.backend.disabled)
        #expect(f.backend.writes == [true, false])
        #expect(f.store.record?.intent == .restoreLidPolicy && f.store.record?.disposition == .acknowledged)
    }

    @Test func restoresARecordFromAnotherBoot() {
        let f = acquired()
        #expect(f.makeService(bootID: "boot-b").recoverOrphanedPolicy(graceSeconds: 10) == .restored)
        #expect(!f.backend.disabled)
    }

    @Test func acknowledgesWithoutWritingWhenThePolicyIsAlreadyClear() {
        let f = acquired()
        f.backend.disabled = false
        f.time = 200
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .restored)
        #expect(f.backend.writes == [true])
    }

    @Test func leavesUncertainOrAbsentRecordsAlone() {
        let empty = Fixture()
        #expect(empty.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .nothingToRecover)
        let f = Fixture()
        f.backend.writeFails = true
        #expect(!f.acquire().accepted)
        f.backend.writeFails = false
        f.backend.disabled = true
        f.time = 500
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .nothingToRecover)
        #expect(f.backend.writes == [true])
    }

    @Test func aRacingJournalWriterMakesRecoveryFailInsteadOfOverwriting() {
        let f = acquired()
        f.time = 200
        f.store.failAt = f.store.commits + 1
        let outcome = f.makeService().recoverOrphanedPolicy(graceSeconds: 10)
        guard case .failed = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(f.store.record?.intent == .enableLidOverride)
    }

    @Test func aSecondRecoveryAfterSuccessIsANoOp() {
        let f = acquired()
        f.time = 200
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .restored)
        #expect(f.makeService().recoverOrphanedPolicy(graceSeconds: 10) == .nothingToRecover)
        #expect(f.backend.writes == [true, false])
    }
}

@Suite struct SessionIsolationTests {
    @Test func aSecondClientIsRefusedWhileALeaseIsActive() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        let second = f.service.handle(PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 60),
                                      owner: UUID(), uid: 501)
        #expect(!second.accepted)
        #expect(f.backend.writes == [true])
    }

    @Test func anUnreadableJournalBlocksNewSessionsWithoutWriting() {
        let f = Fixture()
        f.store.loadFails = true
        #expect(!f.acquire().accepted)
        #expect(f.service.state == "recoveryRequired")
        #expect(f.backend.writes.isEmpty)
    }
}
