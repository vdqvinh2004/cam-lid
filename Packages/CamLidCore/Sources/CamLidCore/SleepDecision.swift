import Foundation

/// Extends the existing restoration gate; this decision never actuates power.
public struct GuardedSleepDecision: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let eligible: Bool
    public let blockers: [String]
    public let outcome: String
    public static func evaluate(now: Double, observedAt: Double, lid: LidState,
        displaysObservedAt: Double, displays: DisplayState,
        inputObservedAt: Double,
        idleSeconds: Double?, workActive: Bool, workUnknown: Bool, restore: RestoreState,
        backendVerified: Bool) -> Self {
        var reasons: [String] = []
        if !isFresh(observedAt, now: now) { reasons.append("telemetryStale") }
        if !isFresh(displaysObservedAt, now: now) { reasons.append("displayStale") }
        if !isFresh(inputObservedAt, now: now) { reasons.append("inputStale") }
        if lid != .closed {
            if displays == .unknown { reasons.append("displayUnknown") }
            else if displays != .asleep { reasons.append("displayAwake") }
        }
        if let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 {
            if idleSeconds < 60 { reasons.append("inUse") }
        } else { reasons.append("inputUnknown") }
        if workActive { reasons.append("trackedWorkActive") }
        if workUnknown { reasons.append("workUnknown") }
        if restore != .verified { reasons.append("restorationUnverified") }
        if !backendVerified { reasons.append("previewOnly") }
        return Self(schemaVersion: 1, eligible: reasons.isEmpty, blockers: reasons,
            outcome: reasons.isEmpty ? "notRequested" : "blocked")
    }

    private static func isFresh(_ sampledAt: Double, now: Double) -> Bool {
        now.isFinite && now >= 0 && sampledAt.isFinite && sampledAt >= 0
            && sampledAt <= now && now - sampledAt <= 5
    }
}
