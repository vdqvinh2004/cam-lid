import Foundation
import LidRecoveryJournal
// The helper, its tests and the QA client keep using the wire types through this module.
@_exported import CamLidPowerWire

public struct HelperSafety: Sendable {
    public let onAC: Bool
    public let batteryPercent: Double?
    public let thermalNominal: Bool
    public let consoleUID: UInt32?
    public let lidClosed: Bool?
    public let externalDisplays: Int?

    public init(onAC: Bool, batteryPercent: Double?, thermalNominal: Bool, consoleUID: UInt32?,
                lidClosed: Bool?, externalDisplays: Int?) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
        self.thermalNominal = thermalNominal
        self.consoleUID = consoleUID
        self.lidClosed = lidClosed
        self.externalDisplays = externalDisplays
    }

    func permits(_ uid: UInt32) -> Bool {
        onAC && thermalNominal && consoleUID == uid && lidClosed != nil && externalDisplays == 0 &&
        batteryPercent.map { $0.isFinite && (20...100).contains($0) } == true
    }
}

public protocol SleepOverrideBackend: AnyObject {
    func readDisabled() throws -> Bool
    func setDisabled(_ disabled: Bool) throws
}

public protocol PowerIntentStore: AnyObject {
    func load() throws -> JournalEntry?
    func commit(_ entry: JournalEntry, replacing revision: UInt64?) throws
}

extension DurableRecoveryJournal: PowerIntentStore {}

public enum PowerServiceFailure: Error { case clock, journal, backend, unsafe, invalidRequest }

/// Confined to the helper's serial queue. Real backend and fake tests share this controller.
/// Helper/process/OS hangs and same-value foreign writes are NOT solved by this lease.
public final class PowerLeaseService {
    public static let heartbeatSeconds = 10
    public static let leaseSeconds = 30.0
    public static let maximumSafetyReadSeconds = 1.0
    public static let maximumSessionSeconds = 4 * 60 * 60

    private struct Lease {
        let token: UUID
        let owner: UUID
        let uid: UInt32
        let cap: Double
        var deadline: Double
        var sequence: UInt64
    }

    private let mechanism: any LeasePowerMechanism
    private let store: any PowerIntentStore
    private let clock: () -> Double
    private let safety: () throws -> HelperSafety
    private let bootID: String
    private var lastTime: Double?
    private var record: JournalEntry?
    private var lease: Lease?
    private var activationLease: Lease?
    private var restoreAttempted = false
    private var terminalEventReason: String?
    /// Diagnostic sink for state transitions only (never request payloads); a no-op unless the host sets it.
    public var log: (String) -> Void = { _ in }
    public private(set) var state = "starting"
    public private(set) var reason = "notStarted"
    public private(set) var mutationAttempted = false

    public convenience init(backend: any SleepOverrideBackend, store: any PowerIntentStore, bootID: String,
                            clock: @escaping () -> Double, safety: @escaping () throws -> HelperSafety) {
        self.init(mechanism: GlobalSleepMechanism(backend), store: store, bootID: bootID, clock: clock, safety: safety)
    }

    public init(mechanism: any LeasePowerMechanism, store: any PowerIntentStore, bootID: String,
                clock: @escaping () -> Double, safety: @escaping () throws -> HelperSafety) {
        self.mechanism = mechanism
        self.store = store
        self.bootID = bootID
        self.clock = clock
        self.safety = safety
    }

    private func now() throws -> Double {
        let value = clock()
        guard value.isFinite, value >= 0, lastTime.map({ value >= $0 }) ?? true else {
            throw PowerServiceFailure.clock
        }
        lastTime = value
        return value
    }

    private func safe(uid: UInt32, requiresOpen: Bool = false) throws -> Bool {
        let before = try now()
        let reading = try safety()
        let after = try now()
        return after - before <= Self.maximumSafetyReadSeconds && reading.permits(uid) &&
            (!requiresOpen || reading.lidClosed == false)
    }

    public func start() {
        guard state == "starting" else { return }
        do {
            guard !bootID.isEmpty else { throw PowerServiceFailure.clock }
            _ = try now()
            record = try store.load()
            if let record {
                let isLidSpecific = record.ownerIdentity.hasPrefix("lid-specific-v1:")
                guard isLidSpecific == (mechanism.family == "lid-specific-v1") else {
                    throw PowerServiceFailure.journal
                }
            }
            if let record, !(record.intent == .restoreLidPolicy && record.disposition == .acknowledged) {
                state = "recoveryRequired"
                // Never clear an uncertain enable or interrupted restore. Another boot's override is
                // cleared only when its policy persists across reboot and our enable was acknowledged.
                if try mechanism.readApplied() == false {
                    try acknowledgeRestored()
                } else if record.bootID == bootID || mechanism.restoresOwnedPolicyAfterReboot,
                          record.intent == .enableLidOverride && record.disposition == .acknowledged
                            || finishesInterruptedRestore(record) {
                    // Re-observe before a restart cleanup. A foreign policy still permits the
                    // own one-shot lid clear, but the final state must stay recovery-required.
                    let foreign = (try? mechanism.readForeignPolicy()) ?? .unreadable
                    switch foreign {
                    case .conflicted:
                        try restore(reason: "foreignGlobalSleepDisabled")
                    case .unreadable:
                        try restore(reason: "foreignPolicyUnreadable")
                    case .clear:
                        try restore(reason: "helperRestart")
                    }
                } else {
                    reason = "uncertainPreviousMutation"
                }
            } else if record != nil, mechanism.family == "lid-specific-v1" {
                // A restart can lose the in-memory foreign-stop reason. Re-observe the
                // read-only policy before calling the old cleanup benign; never clear it.
                let foreign = (try? mechanism.readForeignPolicy()) ?? .unreadable
                switch foreign {
                case .clear:
                    state = "cleanupAcknowledged"
                    reason = "sharedLidRestorationUnverified"
                case .conflicted:
                    state = "recoveryRequired"
                    reason = "foreignGlobalSleepDisabled"
                case .unreadable:
                    state = "recoveryRequired"
                    reason = "foreignPolicyUnreadable"
                }
            } else {
                state = "ready"
                reason = "noPendingIntent"
            }
        } catch {
            if case JournalFailure.revisionConflict = error, adoptRestoreWrittenElsewhere() {
                // The recovery job (started together with us at load) finished the same restore first.
            } else {
                log("start failed: \(error)")
                state = "recoveryRequired"
                reason = "startupInspectionFailed"
            }
        }
        log("start state=\(state) reason=\(reason)")
    }

    public enum OrphanRecovery: Equatable, Sendable {
        case nothingToRecover, leaseStillValid, restored, failed(String)
    }

    /// One-shot recovery for a process other than the running helper (hung, killed or never restarted).
    /// Acts only on an acknowledged enable whose lease deadline plus grace has passed, or one from
    /// another boot, and only for a policy that survives reboot. Uncertain journal entries are left
    /// for inspection. A racing journal writer makes the restore fail and the caller retries.
    public func recoverOrphanedPolicy(graceSeconds: Double) -> OrphanRecovery {
        guard state == "starting", mechanism.restoresOwnedPolicyAfterReboot else { return .nothingToRecover }
        do {
            let current = try now()
            guard let loaded = try store.load(),
                  loaded.intent == .enableLidOverride && loaded.disposition == .acknowledged
                    || finishesInterruptedRestore(loaded) else { return .nothingToRecover }
            record = loaded
            let deadline = Double(loaded.continuousDeadlineNanos) / 1_000_000_000
            // A pending restore has no lease to wait for, and its copied deadline may come from another boot's clock.
            let expired = finishesInterruptedRestore(loaded) || loaded.bootID != bootID || current > deadline + graceSeconds
            log("recover record=\(loaded.intent) boot=\(loaded.bootID == bootID ? "same" : "other") now=\(current) deadline=\(deadline) grace=\(graceSeconds) expired=\(expired)")
            guard expired else { return .leaseStillValid }
            if try mechanism.readApplied() == false {
                try acknowledgeRestored()
                return .restored
            }
            try restore(reason: "independentRecovery")
            return state == "restored" ? .restored : .failed(reason)
        } catch {
            return .failed("recoveryFailed")
        }
    }

    public func handle(_ request: PowerRequest, owner: UUID, uid: UInt32) -> PowerReply {
        if request.operation != .inspect { log("request \(request.operation.rawValue)") }
        poll()
        guard request.version == 1 else { return reply(false, "unsupportedProtocol") }
        do {
            switch request.operation {
            case .inspect:
                return reply(true, reason)
            case .acquire:
                guard state == "ready" || state == "restored", terminalEventReason == nil else {
                    return reply(false, "notReady")
                }
                guard request.token == nil, request.sequence == 1,
                      let seconds = request.sessionSeconds,
                      (1...mechanism.maximumSessionSeconds).contains(seconds), uid > 0 else {
                    return reply(false, "invalidRequest")
                }
                let start = try now()
                guard try safe(uid: uid, requiresOpen: true) else { return reply(false, "safetyRefused") }
                guard try mechanism.admissionAllowed() else { return reply(false, "preexistingOverride") }
                guard try now() < start + mechanism.leaseSeconds else { return reply(false, "admissionExpired") }
                let token = UUID()
                let pending = Lease(token: token, owner: owner, uid: uid, cap: start + Double(seconds),
                                    deadline: min(start + mechanism.leaseSeconds, start + Double(seconds)), sequence: 1)
                restoreAttempted = false
                try save(intent: .enableLidOverride, disposition: .pending, lease: pending)
                // A slow fsync/safety check must not authorize an already expired mutation.
                guard terminalEventReason == nil, try now() < pending.deadline,
                      try safe(uid: uid, requiresOpen: true), try now() < pending.deadline else {
                    state = "recoveryRequired"
                    reason = "admissionExpiredBeforeWrite"
                    return reply(false, reason)
                }
                guard try mechanism.admissionAllowed(), terminalEventReason == nil,
                      try now() < pending.deadline else {
                    state = "recoveryRequired"
                    reason = "admissionChangedBeforeWrite"
                    return reply(false, reason)
                }
                state = "enabling"
                activationLease = pending
                mutationAttempted = true
                let remaining = (pending.deadline - (try now())) * 1_000_000_000
                let minimum = mechanism.family == "lid-specific-v1" ? 1_000_000_000.0 : 1.0
                guard remaining.isFinite, remaining >= minimum, remaining < Double(UInt64.max) else {
                    throw PowerServiceFailure.clock
                }
                try mechanism.apply(remainingNanos: UInt64(remaining), episodeID: token)
                lease = pending
                activationLease = nil
                guard terminalEventReason == nil, try now() < pending.deadline else {
                    throw PowerServiceFailure.unsafe
                }
                if try mechanism.readApplied() == false { throw PowerServiceFailure.backend }
                try save(intent: .enableLidOverride, disposition: .acknowledged, lease: pending)
                guard terminalEventReason == nil, try now() < pending.deadline else {
                    throw PowerServiceFailure.unsafe
                }
                state = "active"
                reason = "leaseAcquired"
                poll()
                return reply(state == "active", reason, token: state == "active" ? token : nil)
            case .renew:
                guard var current = lease, state == "active", current.owner == owner,
                      current.uid == uid, current.token == request.token,
                      let sequence = request.sequence, sequence > current.sequence,
                      request.sessionSeconds == nil else { return reply(false, "invalidLease") }
                let time = try now()
                guard terminalEventReason == nil, time < current.deadline, time < current.cap,
                      try safe(uid: uid) else {
                    try restore(reason: terminalEventReason ?? "renewalRefused")
                    return reply(false, terminalEventReason ?? "renewalRefused")
                }
                let oldDeadline = current.deadline
                current.deadline = min(time + mechanism.leaseSeconds, current.cap)
                current.sequence = sequence
                let remaining = (current.deadline - (try now())) * 1_000_000_000
                let minimum = mechanism.family == "lid-specific-v1" ? 1_000_000_000.0 : 1.0
                guard remaining.isFinite, remaining >= minimum, remaining < Double(UInt64.max) else {
                    throw PowerServiceFailure.clock
                }
                try mechanism.prepareRenewal(remainingNanos: UInt64(remaining), episodeID: current.token)
                guard terminalEventReason == nil, try now() < oldDeadline,
                      try now() < current.deadline, try now() < current.cap else {
                    try restore(reason: terminalEventReason ?? "renewalExpiredDuringCommit")
                    return reply(false, terminalEventReason ?? "renewalExpiredDuringCommit")
                }
                try save(intent: .enableLidOverride, disposition: .acknowledged, lease: current)
                guard terminalEventReason == nil, try now() < oldDeadline,
                      try now() < current.deadline, try now() < current.cap else {
                    try restore(reason: terminalEventReason ?? "renewalExpiredDuringCommit")
                    return reply(false, terminalEventReason ?? "renewalExpiredDuringCommit")
                }
                try mechanism.completeRenewal()
                guard terminalEventReason == nil, try now() < oldDeadline,
                      try now() < current.deadline, try now() < current.cap else {
                    try restore(reason: terminalEventReason ?? "renewalExpiredDuringCommit")
                    return reply(false, terminalEventReason ?? "renewalExpiredDuringCommit")
                }
                lease = current
                return reply(true, "leaseRenewed", token: current.token)
            case .release:
                guard let current = lease, current.owner == owner, current.uid == uid,
                      current.token == request.token else { return reply(false, "invalidLease") }
                try restore(reason: "clientRelease")   // the client may release for Stop, a cap or a safety stop
                return reply(state == "restored", reason)
            }
        } catch {
            // A retained successful write permits rollback; an uncertain write never does.
            if lease == nil, mechanism.applyAcknowledged { lease = activationLease }
            activationLease = nil
            if lease != nil {
                do { try restore(reason: terminalEventReason ?? "operationFailedCleanup") }
                catch { state = "recoveryRequired"; reason = "operationFailed" }
            } else {
                try? mechanism.discardOwnedResourcesAfterFailedApply()
                state = "recoveryRequired"
                reason = "operationFailed"
            }
            return reply(false, reason)
        }
    }

    public func observeSystemEvent(reason eventReason: String) {
        if terminalEventReason == nil { terminalEventReason = eventReason }
        let finalReason = terminalEventReason ?? eventReason
        if lease != nil, state == "active" {
            do { try restore(reason: finalReason) }
            catch { state = "recoveryRequired"; reason = "restorationFailed" }
        } else if state == "ready" || state == "restored" {
            state = "stopped"
            reason = finalReason
        }
    }

    public func poll() {
        guard let current = lease, state == "active" else { return }
        let stopReason: String?
        do {
            let time = try now()
            if time >= current.cap { stopReason = "sessionExpired" }
            else if time >= current.deadline { stopReason = "heartbeatExpired" }
            else {
                let healthy = try safe(uid: current.uid)
                if healthy {
                    let overrideStillSet = try mechanism.readApplied()
                    // This is a read-only coexistence check. A failed read is unknown, never
                    // clear, and never authorizes a global write.
                    let foreign = (try? mechanism.readForeignPolicy()) ?? .unreadable
                    let after = try now()
                    if after >= current.cap { stopReason = "sessionExpired" }
                    else if after >= current.deadline { stopReason = "heartbeatExpired" }
                    else if foreign == .conflicted { stopReason = "foreignGlobalSleepDisabled" }
                    else if foreign == .unreadable { stopReason = "foreignPolicyUnreadable" }
                    else { stopReason = overrideStillSet == false ? "overrideChanged" : nil }
                } else {
                    let after = try now()
                    if after >= current.cap { stopReason = "sessionExpired" }
                    else if after >= current.deadline { stopReason = "heartbeatExpired" }
                    else { stopReason = "safetyStop" }
                }
            }
        } catch { stopReason = "monitorFailed" }
        if let stopReason {
            log("poll stop reason=\(stopReason)")
            do { try restore(reason: stopReason) }
            catch { state = "recoveryRequired"; reason = "restorationFailed" }
        }
    }

    public func disconnected(owner: UUID) {
        guard lease?.owner == owner else { return }
        do { try restore(reason: "clientDisconnected") }
        catch { state = "recoveryRequired"; reason = "restorationFailed" }
    }

    public func shutdown() {
        guard lease != nil else { return }
        do { try restore(reason: "helperStopping") }
        catch { state = "recoveryRequired"; reason = "restorationFailed" }
    }

    /// Another process (the recovery job) committed to the journal first. If it already finished a restore and the
    /// policy reads back as cleared, take that result; otherwise the caller reports the failure as before.
    private func adoptRestoreWrittenElsewhere() -> Bool {
        guard let latest = try? store.load(), latest.intent == .restoreLidPolicy, latest.disposition == .acknowledged,
              (try? mechanism.readApplied()) == false else { return false }
        record = latest
        lease = nil
        state = "restored"
        reason = "restorationVerified"
        log("adopted a restore written by another process")
        return true
    }

    /// A pending restore is journaled only after an acknowledged enable of our own, so for a policy that survives
    /// reboot (global `SleepDisabled`) finishing it writes the default back. Without this, a restore cut off by
    /// shutdown left the Mac unable to sleep after the next boot (G2 trial 7).
    private func finishesInterruptedRestore(_ entry: JournalEntry) -> Bool {
        mechanism.restoresOwnedPolicyAfterReboot && entry.intent == .restoreLidPolicy && entry.disposition == .pending
    }

    private func restore(reason stopReason: String) throws {
        log("restore begin reason=\(stopReason)")
        defer { log("restore end state=\(state) reason=\(reason)") }
        guard let record else { throw PowerServiceFailure.journal }
        // Only completed enables or this process's retained success authorize a write.
        guard record.disposition == .acknowledged && record.intent == .enableLidOverride || lease != nil
                || finishesInterruptedRestore(record) else {
            throw PowerServiceFailure.journal
        }
        guard !restoreAttempted else { throw PowerServiceFailure.backend }
        // A failed/lost cleanup result is not authority to dispatch another global write.
        restoreAttempted = true
        state = "restoring"
        let isForeignStop = stopReason == "foreignGlobalSleepDisabled"
            || stopReason == "foreignPolicyUnreadable"
        do {
            try save(intent: .restoreLidPolicy, disposition: .pending, lease: lease)
            mutationAttempted = true
            switch try mechanism.clear() {
            case .verifiedReadback:
                try acknowledgeRestored()
                if isForeignStop {
                    state = "recoveryRequired"
                    reason = stopReason
                }
            case .callsAcknowledgedOnly:
                try save(intent: .restoreLidPolicy, disposition: .acknowledged, lease: lease)
                lease = nil
                state = isForeignStop ? "recoveryRequired" : "cleanupAcknowledged"
            }
            reason = stopReason
        } catch {
            if case JournalFailure.revisionConflict = error, adoptRestoreWrittenElsewhere() { return }
            log("restore failed: \(error)")
            mechanism.releaseOwnedResourcesAfterFailedRestore()
            throw error
        }
    }

    private func acknowledgeRestored() throws {
        try save(intent: .restoreLidPolicy, disposition: .acknowledged, lease: lease)
        lease = nil
        state = "restored"
        reason = "restorationVerified"
    }

    private func save(intent: JournalEntry.Intent, disposition: JournalEntry.Disposition, lease: Lease?) throws {
        let (next, overflow) = (record?.revision ?? 0).addingReportingOverflow(1)
        guard !overflow else {
            throw PowerServiceFailure.journal
        }
        let deadline: UInt64
        if let lease {
            let value = lease.deadline * 1_000_000_000
            guard value.isFinite, value > 0, value < Double(UInt64.max) else { throw PowerServiceFailure.clock }
            deadline = UInt64(value)
        } else {
            guard let previous = record else { throw PowerServiceFailure.journal }
            deadline = previous.continuousDeadlineNanos
        }
        let familyPrefix = mechanism.family == "lid-specific-v1" ? "lid-specific-v1:" : ""
        let entry = JournalEntry(revision: next, sessionID: lease?.token.uuidString ?? record!.sessionID,
            ownerIdentity: lease.map { "\(familyPrefix)uid:\($0.uid):connection:\($0.owner.uuidString)" } ?? record!.ownerIdentity,
            bootID: bootID, generation: record?.generation ?? 1,
            operationID: UUID().uuidString, intent: intent, disposition: disposition,
            continuousDeadlineNanos: deadline)
        try store.commit(entry, replacing: record?.revision)
        record = entry
    }

    private func reply(_ accepted: Bool, _ reason: String, token: UUID? = nil) -> PowerReply {
        log("reply accepted=\(accepted) reason=\(reason) state=\(state)")
        let time = clock()
        let valid = time.isFinite && lastTime.map { time >= $0 } == true
        return PowerReply(accepted: accepted, state: state, reason: reason, token: token,
            leaseRemainingSeconds: valid ? lease.map { max(0, $0.deadline - time) } : nil,
            sessionRemainingSeconds: valid ? lease.map { max(0, $0.cap - time) } : nil,
            mutationAttempted: mutationAttempted, mechanismFamily: mechanism.family)
    }
}

