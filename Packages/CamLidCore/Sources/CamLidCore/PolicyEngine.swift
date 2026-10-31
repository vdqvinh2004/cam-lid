/// Shared protection-state policy. Pure function of (session, tasks, health,
/// config, signals, monotonic time) so the simulator, CLI and app share one policy.
/// Uses a continuous monotonic clock: jumps forward expire grace/cap exactly as elapsed
/// wall time would, including time spent asleep.
public struct PolicyDecision: Sendable, Equatable {
    public let state: EffectiveState
    /// Stable machine reason codes; human messages may change (contracts/cli.md).
    public let reasons: [String]
    public let session: ProtectionSession
}

public enum PolicyEngine {
    /// Protected commands may join only an existing Auto session. Persisted
    /// defaults never count as an active session, and every safety/backend
    /// uncertainty fails closed.
    public static func mayAdmitCommand(
        session: ProtectionSession?,
        backendVerified: Bool,
        safetyClear: Bool,
        nowMonotonic: Double
    ) -> Bool {
        guard let session,
              session.requestedMode == .auto,
              !session.latchedSafetyStop,
              backendVerified, safetyClear,
              nowMonotonic.isFinite,
              nowMonotonic >= session.startedAtMonotonic,
              session.capDeadlineMonotonic.map({ nowMonotonic < $0 }) ?? true else {
            return false
        }
        switch session.effectiveState {
        case .off, .safetyStopped, .expired, .unavailable, .recoveryRequired:
            return false
        case .ready, .protected, .completionGrace:
            return true
        }
    }

    /// Single evaluation step. Returns the updated session (revision+1 on any change).
    public static func evaluate(
        session: ProtectionSession,
        tasks: [AgentTask],
        health: HealthSnapshot,
        config: Configuration,
        armed: Bool,
        safety: SafetySignal,
        recoveryConflict: Bool,
        completionUncertain: Bool = false,
        lifetimeHoldReason: String? = nil,
        lifetimeCompletionSuppressed: Bool = false,
        nowMonotonic: Double
    ) -> PolicyDecision {
        var updated = session

        func transition(_ state: EffectiveState, reasons: [String]) -> PolicyDecision {
            if updated.effectiveState != state { updated.stateRevision += 1 }
            updated.effectiveState = state
            return PolicyDecision(state: state, reasons: reasons, session: updated)
        }

        // Recovery conflict outranks everything except active safety (safety first).
        // Sensors read as unknown for a moment after a wake (trial 8). While nothing is held, missing readings
        // only block holding; they do not latch a stop the owner must clear by hand.
        if !safety.reasons.isEmpty, updated.effectiveState == .ready, !updated.latchedSafetyStop,
           safety.reasons.allSatisfy({ $0.hasSuffix("Unknown") }) {
            return transition(.ready, reasons: safety.reasons)
        }
        if !safety.reasons.isEmpty {
            updated.latchedSafetyStop = true
            updated.stopReasons = safety.reasons
            updated.graceDeadlineMonotonic = nil
            return transition(.safetyStopped, reasons: safety.reasons)
        }
        if updated.latchedSafetyStop {
            return transition(.safetyStopped, reasons: ["safetyLatched"] + updated.stopReasons)
        }
        if recoveryConflict {
            return transition(.recoveryRequired, reasons: ["recoveryConflict"])
        }
        // Cap is nonresetting: once expired, only explicit re-arm (new session) leaves.
        // The cap deadline is never rewritten, so every later tick re-hits this
        // check with the same reason: fresh work can never clear expiry.
        if let cap = updated.capDeadlineMonotonic, nowMonotonic >= cap {
            updated.graceDeadlineMonotonic = nil
            return transition(.expired, reasons: ["capReached"])
        }
        if updated.requestedMode == .off {
            return transition(.off, reasons: ["modeOff"])
        }

        let holding = tasks.filter { holdsSession($0, now: nowMonotonic) }
        updated.taskIDs = Set(holding.map(\.id))
        // Power arming ignores waiting: supervision keeps those tasks for display,
        // but only work (and bounded unknown) may keep the machine awake.
        let powerHolding = tasks.filter { holdsPower($0, now: nowMonotonic) }

        // Timed/manual requested protection holds independently of agent
        // evidence: an armed healthy session stays protected with no tasks.
        // Safety, latch, recovery conflict, cap and modeOff above outrank this.
        if powerHolding.isEmpty
            && (updated.requestedMode == .timed || updated.requestedMode == .manual) && armed
        {
            updated.graceDeadlineMonotonic = nil
            return transition(.protected, reasons: ["requestedProtection"])
        }
        if powerHolding.isEmpty {
            if updated.requestedMode == .auto && armed {
                if let lifetimeHoldReason {
                    updated.graceDeadlineMonotonic = nil
                    return transition(.protected, reasons: [lifetimeHoldReason])
                }
                if lifetimeCompletionSuppressed {
                    updated.graceDeadlineMonotonic = nil
                    return transition(.ready, reasons: ["lifetimeEpochUnconfirmed", "releaseComplete"])
                }
            }
            // Unknown may release its bounded hold, but cannot prove completion
            // or authorize an explicit sleep request.
            if completionUncertain || tasks.contains(where: { $0.state == .unknown }) {
                updated.graceDeadlineMonotonic = nil
                return transition(.ready, reasons: ["workUncertain", "releaseComplete"])
            }
            switch updated.effectiveState {
            case .protected:
                updated.graceDeadlineMonotonic =
                    nowMonotonic + Double(config.completionDelayMinutes) * 60
                return transition(.completionGrace, reasons: ["lastTaskStopped"])
            case .completionGrace:
                if let grace = updated.graceDeadlineMonotonic, nowMonotonic < grace {
                    return transition(.completionGrace, reasons: ["gracePending"])
                }
                updated.graceDeadlineMonotonic = nil
                if health.lidState == .closed {
                    return transition(.ready, reasons: ["graceExpired", "sleepRequested"])
                }
                return transition(.ready, reasons: ["graceExpired", "releaseComplete"])
            default:
                return transition(.ready, reasons: ["noHoldingTask"])
            }
        }

        // Fresh work during grace returns to protected; grace deadline cleared.
        // Cap deadline is intentionally untouched: fresh work never extends the cap.
        updated.graceDeadlineMonotonic = nil
        guard armed else {
            return transition(.ready, reasons: ["notArmed"])
        }
        if updated.requestedMode == .auto {
            let nonProcess = holding.filter { $0.evidenceKind != .process }
            guard !nonProcess.isEmpty else {
                return transition(.ready, reasons: ["processOnlyNoArm"])
            }
        }
        return transition(.protected, reasons: ["holdingTask", "armed"])
    }

    /// A task holds the session while working, while waiting inside its wait
    /// deadline, or while unknown inside its bounded previously-working deadline.
    public static func holdsSession(_ task: AgentTask, now: Double) -> Bool {
        switch task.state {
        case .working:
            return true
        case .waiting:
            guard let until = task.waitUntilMonotonic else { return false }
            return now < until
        case .unknown:
            guard let until = task.unknownUntilMonotonic else { return false }
            return now < until
        case .idle, .completed, .failed:
            return false
        }
    }

    /// Power follows work, not waiting. A task waiting for the user holds
    /// supervision (so the dashboard can show it) but never holds power:
    /// nobody is computing, so there is nothing to keep awake for.
    public static func holdsPower(_ task: AgentTask, now: Double) -> Bool {
        guard task.state != .waiting else { return false }
        return holdsSession(task, now: now)
    }

    /// Explicit user re-arm after a latched safety stop. The only path out of
    /// `.safetyStopped`; holding work alone never clears the latch.
    public static func rearm(_ session: ProtectionSession) -> ProtectionSession {
        var updated = session
        updated.latchedSafetyStop = false
        updated.stopReasons = []
        updated.graceDeadlineMonotonic = nil
        if updated.effectiveState == .safetyStopped {
            updated.effectiveState = .ready
            updated.stateRevision += 1
        }
        return updated
    }
}
