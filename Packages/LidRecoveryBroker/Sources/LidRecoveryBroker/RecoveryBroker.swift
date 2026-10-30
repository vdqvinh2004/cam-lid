import Foundation
@_spi(FaultInjection) import LidRecoveryJournal

public enum StartupState: String, Codable, Sendable {
    case clean, reconciliationRequired
}

/// Non-actuating experiment; no admission ever supplies physical protection.
public final class RecoveryBroker {
    private let journal: DurableRecoveryJournal
    public private(set) var startup: StartupState = .clean

    private let trustedClients: Set<CodeIdentityPin>
    private let environment: any BrokerEnvironment
    private let trustedMonitors: Set<CodeIdentityPin>
    private var lastClock: BrokerClockSnapshot
    private var clockFault: BrokerFailure?
    private var active: (owner: String, lease: InertLease, record: JournalEntry)?
    public static let maximumLeaseNanos: UInt64 = 30_000_000_000
    /// Experimental session limit, not a supported physical-power policy.
    public static let maximumSessionNanos: UInt64 = 3_600_000_000_000

    public convenience init(directory: URL, trustedClients: Set<CodeIdentityPin> = [],
                            trustedMonitors: Set<CodeIdentityPin> = []) throws {
        try self.init(directory: directory, trustedClients: trustedClients,
                      trustedMonitors: trustedMonitors, environment: SystemBrokerEnvironment())
    }

    @_spi(TestInputs)
    public init(directory: URL, trustedClients: Set<CodeIdentityPin> = [],
                trustedMonitors: Set<CodeIdentityPin> = [], environment: any BrokerEnvironment,
                systemCalls: (any JournalSystemCalls)? = nil) throws {
        guard trustedClients.isDisjoint(with: trustedMonitors) else { throw BrokerFailure.ambiguousRoles }
        self.trustedClients = trustedClients
        self.trustedMonitors = trustedMonitors
        self.environment = environment
        lastClock = try environment.sample()
        guard !lastClock.bootID.isEmpty else { throw BrokerFailure.environmentUnavailable }
        if let systemCalls { journal = try DurableRecoveryJournal(directory: directory, systemCalls: systemCalls) }
        else { journal = try DurableRecoveryJournal(directory: directory) }
        startup = try journal.load() == nil ? .clean : .reconciliationRequired
    }

    /// Caller schedules this on the same serialized context as IPC dispatch.
    public func poll() throws { _ = try currentRecord() }

    private func currentRecord() throws -> (clock: BrokerClockSnapshot, record: JournalEntry?) {
        do {
            let clock = try sampleClock()
            var record = try journal.load()
            if record != nil { startup = .reconciliationRequired }
            if let active, record != active.record { self.active = nil }
            if let active, clock.nowNanos >= active.lease.deadlineNanos {
                self.active = nil
                let next = try restoreIntent(after: active.record)
                try journal.commit(next, replacing: active.record.revision)
                record = next
            }
            return (clock, record)
        } catch {
            active = nil
            startup = .reconciliationRequired
            throw error
        }
    }

    private func sampleClock() throws -> BrokerClockSnapshot {
        if let clockFault { throw clockFault }
        let sample: BrokerClockSnapshot
        do { sample = try environment.sample() }
        catch {
            clockFault = .environmentUnavailable
            throw BrokerFailure.environmentUnavailable
        }
        if sample.bootID != lastClock.bootID { clockFault = .bootChanged }
        else if sample.nowNanos < lastClock.nowNanos { clockFault = .clockRegressed }
        if let clockFault { throw clockFault }
        lastClock = sample
        return sample
    }

    /// The caller owns/closes the accepted socket. One bounded frame only.
    public func serveConnection(_ fd: Int32) throws {
        let io = FrameIO(fd: fd)
        let data = try io.read()
        let peer = try SocketPeer(fd: fd)
        guard trustedClients.contains(peer.pin) || trustedMonitors.contains(peer.pin) else {
            let denial = BrokerReply(accepted: false, reason: "unauthorized", startup: nil,
                                     powerActuation: false, protectionAvailable: false)
            try io.write(JSONEncoder().encode(denial))
            return
        }
        let request = try JSONDecoder().decode(BrokerRequest.self, from: data)
        guard request.version == 1 else { throw BrokerFailure.protocolViolation }
        guard request.operation != .recordRestoreIntent || trustedMonitors.contains(peer.pin) else {
            let denial = BrokerReply(accepted: false, reason: "monitorRoleRequired", startup: nil,
                                     powerActuation: false, protectionAvailable: false)
            try io.write(JSONEncoder().encode(denial))
            return
        }
        let clientOperation = request.operation == .admitInertLease ||
            request.operation == .renewInertLease || request.operation == .finishInertLease
        if clientOperation && !trustedClients.contains(peer.pin) {
            try io.write(JSONEncoder().encode(BrokerReply(accepted: false, reason: "clientRoleRequired",
                startup: nil, powerActuation: false, protectionAvailable: false)))
            return
        }
        let (clock, observedRecord) = try currentRecord()
        var record = observedRecord
        if request.operation == .admitInertLease {
            guard startup == .clean, record == nil, active == nil else {
                try io.write(JSONEncoder().encode(BrokerReply(accepted: false, reason: "reconciliationRequired",
                    startup: startup, powerActuation: false, protectionAvailable: false)))
                return
            }
            guard request.sequence == 1, let duration = request.durationNanos,
                  let sessionDuration = request.sessionDurationNanos,
                  duration > 0, duration <= Self.maximumLeaseNanos,
                  sessionDuration > 0, sessionDuration <= Self.maximumSessionNanos else {
                throw BrokerFailure.protocolViolation
            }
            let cap = clock.nowNanos.addingReportingOverflow(sessionDuration)
            let deadline = clock.nowNanos.addingReportingOverflow(min(duration, sessionDuration))
            guard !cap.overflow, !deadline.overflow else { throw BrokerFailure.protocolViolation }
            let lease = InertLease(sessionID: UUID().uuidString, generation: UInt64.random(in: 1...UInt64.max),
                sequence: 1, revision: 1, deadlineNanos: deadline.partialValue, capNanos: cap.partialValue)
            let intent = JournalEntry(revision: 1, sessionID: lease.sessionID, ownerIdentity: peer.ownerIdentity,
                bootID: clock.bootID, generation: lease.generation, operationID: UUID().uuidString,
                intent: .enableLidOverride, disposition: .pending, continuousDeadlineNanos: lease.deadlineNanos)
            do { try journal.commit(intent, replacing: nil) }
            catch { startup = .reconciliationRequired; throw error }
            startup = .reconciliationRequired
            guard try sampleClock().nowNanos < lease.deadlineNanos else { throw BrokerFailure.leaseExpired }
            active = (peer.ownerIdentity, lease, intent)
            var reply = BrokerReply(accepted: true, reason: "inertLeaseAdmitted", startup: startup,
                powerActuation: false, protectionAvailable: false)
            reply.lease = lease
            try io.write(JSONEncoder().encode(reply))
            return
        }
        if request.operation == .finishInertLease {
            guard let active, active.owner == peer.ownerIdentity,
                  request.sessionID == active.lease.sessionID,
                  request.generation == active.lease.generation,
                  request.expectedRevision == active.lease.revision,
                  let sequence = request.sequence, sequence > active.lease.sequence else {
                try io.write(JSONEncoder().encode(BrokerReply(accepted: false, reason: "invalidLeaseRequest",
                    startup: startup, powerActuation: false, protectionAvailable: false)))
                return
            }
            self.active = nil
            let next = try restoreIntent(after: active.record)
            try journal.commit(next, replacing: active.record.revision)
            var reply = BrokerReply(accepted: true, reason: "inertLeaseFinishedUnresolved", startup: startup,
                powerActuation: false, protectionAvailable: false)
            reply.reconciliationReason = .restoreUnresolved
            try io.write(JSONEncoder().encode(reply))
            return
        }
        if request.operation == .renewInertLease {
            guard let active, active.owner == peer.ownerIdentity,
                  request.sessionID == active.lease.sessionID,
                  request.generation == active.lease.generation,
                  request.expectedRevision == active.lease.revision,
                  let sequence = request.sequence, sequence > active.lease.sequence,
                  let duration = request.durationNanos, duration > 0, duration <= Self.maximumLeaseNanos,
                  clock.nowNanos < active.lease.deadlineNanos,
                  clock.nowNanos < active.lease.capNanos, active.lease.revision < UInt64.max else {
                try io.write(JSONEncoder().encode(BrokerReply(accepted: false, reason: "invalidLeaseRequest",
                    startup: startup, powerActuation: false, protectionAvailable: false)))
                return
            }
            var lease = active.lease
            lease.deadlineNanos = clock.nowNanos + min(duration, lease.capNanos - clock.nowNanos)
            lease.sequence = sequence
            lease.revision += 1
            let next = JournalEntry(revision: lease.revision, sessionID: lease.sessionID,
                ownerIdentity: active.owner, bootID: active.record.bootID, generation: lease.generation,
                operationID: UUID().uuidString, intent: .enableLidOverride, disposition: .pending,
                continuousDeadlineNanos: lease.deadlineNanos)
            do { try journal.commit(next, replacing: active.lease.revision) }
            catch { self.active = nil; startup = .reconciliationRequired; throw error }
            guard try sampleClock().nowNanos < min(active.lease.deadlineNanos, lease.deadlineNanos) else {
                self.active = nil
                throw BrokerFailure.leaseExpired
            }
            self.active = (active.owner, lease, next)
            var reply = BrokerReply(accepted: true, reason: "inertLeaseRenewed", startup: startup,
                powerActuation: false, protectionAvailable: false)
            reply.lease = lease
            try io.write(JSONEncoder().encode(reply))
            return
        }
        guard request.operation == .status || request.operation == .recordRestoreIntent else {
            throw BrokerFailure.protocolViolation
        }
        var reason = "status"
        if request.operation == .recordRestoreIntent {
            guard let previous = record, request.expectedRevision == previous.revision,
                  previous.revision < UInt64.max else {
                let denial = BrokerReply(accepted: false, reason: "revisionConflict", startup: nil,
                                         powerActuation: false, protectionAvailable: false)
                try io.write(JSONEncoder().encode(denial))
                return
            }
            active = nil
            let next = try restoreIntent(after: previous)
            try journal.commit(next, replacing: previous.revision)
            record = next
            reason = "restoreIntentRecorded"
        }
        if record != nil { startup = .reconciliationRequired }
        var reply = BrokerReply(accepted: true, reason: reason, startup: startup,
                                powerActuation: false, protectionAvailable: false)
        reply.lease = active?.lease
        if let record {
            reply.reconciliationReason = record.bootID != clock.bootID ? .previousBoot :
                record.intent == .restoreLidPolicy ? .restoreUnresolved :
                clock.nowNanos >= record.continuousDeadlineNanos ? .deadlineExpired : .savedIntent
        }
        try io.write(JSONEncoder().encode(reply))
    }
}
