import Foundation
@_spi(FaultInjection) import LidRecoveryJournal

public struct InertRecoveryResult: Codable, Sendable {
    public let reason: String
    public let revision: UInt64?
    public let powerActuation: Bool
    public let protectionAvailable: Bool
}

/// Journal-only experiment. Caller owns scheduling; no service is installed.
public final class InertRecoveryExecutor {
    private let journal: DurableRecoveryJournal
    private let environment: any BrokerEnvironment
    private var lastClock: BrokerClockSnapshot
    private var fault: (any Error)?
    private var observedRecord = false
    private var restoreRequiredAfterContention = false

    public convenience init(directory: URL) throws {
        try self.init(directory: directory, environment: SystemBrokerEnvironment())
    }

    @_spi(TestInputs)
    public init(directory: URL, environment: any BrokerEnvironment,
                systemCalls: (any JournalSystemCalls)? = nil) throws {
        self.environment = environment
        lastClock = try environment.sample()
        guard !lastClock.bootID.isEmpty else { throw BrokerFailure.environmentUnavailable }
        if let systemCalls { journal = try DurableRecoveryJournal(directory: directory, systemCalls: systemCalls) }
        else { journal = try DurableRecoveryJournal(directory: directory) }
    }

    private func sampleClock() throws -> BrokerClockSnapshot {
        let clock = try environment.sample()
        guard clock.bootID == lastClock.bootID else { throw BrokerFailure.bootChanged }
        guard clock.nowNanos >= lastClock.nowNanos else { throw BrokerFailure.clockRegressed }
        lastClock = clock
        return clock
    }

    private func loadObservedRecord() throws -> JournalEntry? {
        let record = try journal.load()
        if record != nil { observedRecord = true }
        else if observedRecord { throw BrokerFailure.journalDisappeared }
        return record
    }

    public func reconcile(brokerPath: String, serverPin: CodeIdentityPin) throws -> InertRecoveryResult {
        if let fault { throw fault }
        do {
            var clock = try sampleClock()
            guard var record = try loadObservedRecord() else {
                return InertRecoveryResult(reason: restoreRequiredAfterContention ? "noRecordUnresolved" : "noRecord", revision: nil,
                    powerActuation: false, protectionAvailable: false)
            }
            if record.intent == .restoreLidPolicy {
                return InertRecoveryResult(reason: "alreadyUnresolved", revision: record.revision,
                    powerActuation: false, protectionAvailable: false)
            }
            var reason = restoreRequiredAfterContention ? "journalContentionRecoveryUnresolved" :
                record.bootID != clock.bootID ? "previousBootUnresolved" : "deadlineExpiredUnresolved"
            if !restoreRequiredAfterContention, record.bootID == clock.bootID,
               clock.nowNanos < record.continuousDeadlineNanos {
                let reply: BrokerReply?
                do { reply = try BrokerConnection.exchange(path: brokerPath, serverPin: serverPin, request: BrokerRequest()) }
                catch { reply = nil }
                clock = try sampleClock()
                guard let latest = try loadObservedRecord() else { throw BrokerFailure.journalDisappeared }
                record = latest
                if record.intent == .restoreLidPolicy {
                    return InertRecoveryResult(reason: "alreadyUnresolved", revision: record.revision,
                        powerActuation: false, protectionAvailable: false)
                }
                if let reply, reply.accepted, !reply.protectionAvailable, !reply.powerActuation,
                   let lease = reply.lease, lease.sessionID == record.sessionID,
                   lease.generation == record.generation, lease.revision == record.revision,
                   lease.deadlineNanos == record.continuousDeadlineNanos,
                   clock.bootID == record.bootID, clock.nowNanos < lease.deadlineNanos {
                    return InertRecoveryResult(reason: "waiting", revision: record.revision,
                        powerActuation: false, protectionAvailable: false)
                }
                reason = reply == nil ? "brokerUnresponsiveUnresolved" : "brokerLeaseMismatchUnresolved"
            }
            let next = try restoreIntent(after: record)
            try journal.commit(next, replacing: record.revision)
            return InertRecoveryResult(reason: reason, revision: next.revision,
                powerActuation: false, protectionAvailable: false)
        } catch {
            if let failure = error as? JournalFailure, failure == .busy || failure == .revisionConflict {
                // Retry only toward unresolved restore intent; never resume waiting/lease state.
                restoreRequiredAfterContention = true
                return InertRecoveryResult(reason: failure == .busy ? "journalBusyUnresolved" : "journalConflictUnresolved",
                    revision: nil, powerActuation: false, protectionAvailable: false)
            }
            fault = error
            throw error
        }
    }
}
