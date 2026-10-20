import Foundation
import CamLidCore

/// Owned-only recovery against `RecoveryJournal` (+ sleep-request evidence).
/// Dry-run is the default and never mutates: it only reads the journal.
/// (T024; contract: power-helper.md restricted `recoverOwnedState`.)
///
/// F04 honesty: dry-run reports `restorable`, never `verified`. Apply requires
/// a reachable recovery service with a confirming restore readback. A nil or
/// non-confirming service leaves the outcome `unresolved` (exit 5) and never
/// marks the journal verified. Sleep-request evidence is attached only when a
/// verified restore was genuinely observed.
public protocol RecoveryService: Sendable {
    /// Confirms owned backend state after a restore attempt. `true` means an
    /// actual restore readback succeeded; `false` (or throw) means unresolved.
    func verifyRestore() throws -> Bool
}

public struct InMemoryRecoveryService: RecoveryService, Sendable {
    public var shouldVerify: Bool
    public var shouldThrow: Bool

    public init(shouldVerify: Bool, shouldThrow: Bool = false) {
        self.shouldVerify = shouldVerify
        self.shouldThrow = shouldThrow
    }

    public func verifyRestore() throws -> Bool {
        if shouldThrow {
            throw RecoveryServiceError.unavailable
        }
        return shouldVerify
    }
}

public enum RecoveryServiceError: Error, Sendable, Equatable {
    case unavailable
}

public struct RecoveryCommand: Sendable {
    public var journal: RecoveryJournal
    public var ownerIdentity: String
    /// Optional app probe. Owned recovery works WITHOUT the app (nil channel
    /// proceeds journal-only); a present channel is pinged on apply and its
    /// denial/unavailability is reported, never masked.
    public var channel: (any IPCChannel)?
    /// Helper-OS authorization flag. `false` models a denied authorization
    /// flow: every outcome becomes conflict/exit 3 without touching power.
    public var authorized: Bool
    /// Reachable recovery backend. `nil` means unavailable: apply cannot
    /// verify and must stay unresolved (exit 5) without marking the journal.
    public var recoveryService: (any RecoveryService)?

    public init(
        journal: RecoveryJournal, ownerIdentity: String,
        channel: (any IPCChannel)? = nil, authorized: Bool = true,
        recoveryService: (any RecoveryService)? = nil
    ) {
        self.journal = journal
        self.ownerIdentity = ownerIdentity
        self.channel = channel
        self.authorized = authorized
        self.recoveryService = recoveryService
    }

    public enum Outcome: String, Sendable, Codable {
        case verified, restorable, unresolved, conflict, unknown, error
    }

    public struct Diagnosis: Sendable, Equatable {
        public var outcome: Outcome
        public var evidence: [String: String]
        /// 0 verified/restorable, 3 conflict/unauthorized, 5 unresolved.
        public var exitCode: Int
    }

    /// Dry-run reads only (journal provably untouched) and reports restorable
    /// ownership evidence, never verified. Apply contacts the recovery service
    /// and marks verified only when an actual restore readback confirms it;
    /// otherwise the outcome stays unresolved and the journal is untouched.
    /// Sleep evidence is attached only on a genuinely verified restore.
    public mutating func run(sessionID: String, dryRun: Bool, lidState: LidState) -> Diagnosis {
        guard authorized else {
            return Diagnosis(outcome: .conflict, evidence: ["reason": "authDenied"], exitCode: 3)
        }
        do {
            try journal.record(for: sessionID).verifyIntegrity()
        } catch JournalError.corrupt(let id) {
            return Diagnosis(outcome: .error, evidence: ["reason": "journalCorrupt", "session": id], exitCode: 5)
        } catch {
            return Diagnosis(outcome: .unknown, evidence: ["reason": "journalMissing", "session": sessionID], exitCode: 5)
        }
        let (result, evidence) = journal.recoverOwnedState(
            sessionID: sessionID, requester: ownerIdentity, dryRun: dryRun)
        switch result {
        case .conflict:
            return Diagnosis(
                outcome: .conflict,
                evidence: evidence.merging(["owner": ownerIdentity]) { current, _ in current },
                exitCode: 3)
        case .unknown:
            return Diagnosis(outcome: .unknown, evidence: evidence, exitCode: 5)
        case .error:
            return Diagnosis(outcome: .error, evidence: evidence, exitCode: 5)
        case .restorable:
            var merged = evidence.merging(["owner": ownerIdentity]) { current, _ in current }
            if dryRun {
                merged["mode"] = "dryRun"
                return Diagnosis(outcome: .restorable, evidence: merged, exitCode: 0)
            }
            if let probe = channel {
                do {
                    _ = try probe.send(command: .recover, payload: Data())
                } catch let ipc as IPCError {
                    switch ipc {
                    case .unauthorized:
                        return Diagnosis(outcome: .conflict, evidence: ["reason": "authDenied"], exitCode: 3)
                    case .unavailable:
                        return Diagnosis(
                            outcome: .unresolved,
                            evidence: ["reason": "serviceUnavailable", "owner": ownerIdentity],
                            exitCode: 5)
                    case .recoveryRequired:
                        return Diagnosis(outcome: .unknown, evidence: ["reason": "recoveryRequired"], exitCode: 5)
                    case .invalidInput(let detail), .policyDenied(let detail):
                        return Diagnosis(outcome: .error, evidence: ["reason": detail], exitCode: 5)
                    case .tooLarge(let size):
                        return Diagnosis(outcome: .error, evidence: ["reason": "payloadTooLarge", "size": "\(size)"], exitCode: 5)
                    }
                } catch {
                    return Diagnosis(outcome: .error, evidence: ["reason": "transportFailed"], exitCode: 5)
                }
            }
            guard let service = recoveryService else {
                return Diagnosis(
                    outcome: .unresolved,
                    evidence: ["reason": "serviceUnavailable", "owner": ownerIdentity],
                    exitCode: 5)
            }
            let confirmed: Bool
            do {
                confirmed = try service.verifyRestore()
            } catch {
                return Diagnosis(
                    outcome: .unresolved,
                    evidence: ["reason": "readbackFailed", "owner": ownerIdentity],
                    exitCode: 5)
            }
            guard confirmed else {
                return Diagnosis(
                    outcome: .unresolved,
                    evidence: ["reason": "restoreUnconfirmed", "owner": ownerIdentity],
                    exitCode: 5)
            }
            try? journal.markRestore(sessionID: sessionID, outcome: .verified)
            merged["sleep"] = sleepEvidence(lidState: lidState)
            return Diagnosis(outcome: .verified, evidence: merged, exitCode: 0)
        }
    }

    private func sleepEvidence(lidState: LidState) -> String {
        switch PowerController.sleepRequest(lidState: lidState, restore: .verified) {
        case .request: return "request"
        case .hold(let reason): return "hold:\(reason)"
        case .blocked(let reason): return "blocked:\(reason)"
        }
    }
}
