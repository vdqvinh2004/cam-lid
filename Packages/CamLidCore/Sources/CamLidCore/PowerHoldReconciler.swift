import Foundation

/// Neutral projection of the helper's reply, so the policy side does not depend on the XPC wire package.
public struct HoldReply: Equatable, Sendable {
    public let accepted: Bool
    public let state: String
    public let reason: String
    public let token: UUID?

    public init(accepted: Bool, state: String, reason: String, token: UUID? = nil) {
        self.accepted = accepted; self.state = state; self.reason = reason; self.token = token
    }
}

public enum HoldAction: Equatable, Sendable {
    /// `strict` asks for the lid-only mechanism (ADR 0003) instead of Standard. `batteryFloor` allows battery power
    /// down to that percent; nil means the helper requires the charger.
    case acquire(sessionSeconds: Int, strict: Bool = false, batteryFloor: Int? = nil)
    case renew(token: UUID, sequence: UInt64)
    case release(token: UUID)
}

public enum HoldStatus: Equatable, Sendable {
    case inactive, acquiring, held, releasing
    /// The helper declined or ended the lease. Not retried within the same desired episode.
    case refused(String)
    /// Renewals stopped being acknowledged; the helper restores on its own after its lease window.
    case lost
    case releaseFailed(String)
}

/// Turns "should the Mac be held awake" into helper calls. Pure: the caller performs each returned action
/// and reports the outcome with `received` or `failed`. The helper's reply is the only source of truth, and a
/// refusal or stop is never retried around until the desire ends and returns.
public struct PowerHoldReconciler: Sendable {
    public static let heartbeatSeconds = 10.0
    public static let leaseSeconds = 30.0
    public static let maximumSessionSeconds = 4 * 60 * 60
    public static let minimumSessionSeconds = 5.0
    public static let unavailableRetrySeconds = 10.0
    public static let releaseRetrySeconds = 5.0

    public private(set) var status: HoldStatus = .inactive
    /// What the shared sleep gate may rely on. Nothing held and nothing uncertain counts as verified.
    public private(set) var restoration: RestoreState = .verified
    public private(set) var unavailableReason: String?

    private var token: UUID?
    private var sequence: UInt64 = 1
    private var lastAccepted: Double?
    private var lastRenewSent: Double?
    private var inFlight: HoldAction?
    private var retryAt: Double?

    public init() {}

    public func leaseVerified(now: Double) -> Bool {
        guard status == .held, let lastAccepted, now >= lastAccepted else { return false }
        return now - lastAccepted < Self.leaseSeconds
    }

    /// Machine reasons the policy should treat as a stop of the closed-lid session.
    public var stopReasons: [String] {
        switch status {
        case .refused(let reason): ["helper:" + reason]
        case .lost: ["helperLeaseLost"]
        case .releaseFailed: ["helperReleaseFailed"]
        default: []
        }
    }

    public mutating func next(desired: Bool, remainingSessionSeconds: Double?, now: Double, strict: Bool = false,
                              batteryFloor: Int? = nil) -> HoldAction? {
        guard inFlight == nil, now.isFinite else { return nil }
        if !desired { return nextWhenNotDesired(now: now) }
        switch status {
        case .inactive:
            if let retryAt, now < retryAt { return nil }
            guard let remaining = remainingSessionSeconds, remaining.isFinite,
                  remaining >= Self.minimumSessionSeconds else { return nil }
            let action = HoldAction.acquire(sessionSeconds: min(Int(remaining), Self.maximumSessionSeconds), strict: strict,
                                            batteryFloor: batteryFloor)
            inFlight = action
            status = .acquiring
            restoration = .pending
            return action
        case .held:
            guard let token, let lastAccepted, let lastRenewSent else { return nil }
            if now - lastAccepted >= Self.leaseSeconds {
                status = .lost
                restoration = .unknown
                return nil
            }
            guard now - lastRenewSent >= Self.heartbeatSeconds else { return nil }
            let action = HoldAction.renew(token: token, sequence: sequence + 1)
            inFlight = action
            self.lastRenewSent = now
            return action
        case .releaseFailed:
            return retryRelease(now: now)
        case .acquiring, .releasing, .refused, .lost:
            return nil
        }
    }

    private mutating func nextWhenNotDesired(now: Double) -> HoldAction? {
        switch status {
        case .held:
            guard let token else { return nil }
            let action = HoldAction.release(token: token)
            inFlight = action
            status = .releasing
            restoration = .pending
            return action
        case .releaseFailed:
            return retryRelease(now: now)
        case .refused, .lost:
            // The episode is over; a later desire starts a fresh acquire.
            status = .inactive
            token = nil; lastAccepted = nil; lastRenewSent = nil
            return nil
        case .inactive:
            retryAt = nil; unavailableReason = nil
            return nil
        case .acquiring, .releasing:
            return nil
        }
    }

    private mutating func retryRelease(now: Double) -> HoldAction? {
        guard let token, retryAt.map({ now >= $0 }) ?? true else { return nil }
        let action = HoldAction.release(token: token)
        inFlight = action
        status = .releasing
        return action
    }

    public mutating func received(_ reply: HoldReply, now: Double) {
        guard let action = inFlight else { return }
        inFlight = nil
        switch action {
        case .acquire:
            if reply.accepted, let issued = reply.token {
                token = issued; sequence = 1; lastAccepted = now; lastRenewSent = now
                status = .held; unavailableReason = nil
            } else {
                status = .refused(reply.reason)
                restoration = Self.restoration(afterStop: reply)
            }
        case .renew(_, let sent):
            if reply.accepted {
                sequence = sent; lastAccepted = now
            } else {
                status = .refused(reply.reason)
                restoration = Self.restoration(afterStop: reply)
            }
        case .release:
            if reply.accepted, reply.state == "restored" {
                status = .inactive; restoration = .verified
                token = nil; lastAccepted = nil; lastRenewSent = nil
            } else {
                status = .releaseFailed(reply.reason); restoration = .failed
                retryAt = now + Self.releaseRetrySeconds
            }
        }
    }

    /// The call did not reach the helper or the connection dropped before a reply.
    public mutating func failed(now: Double) {
        guard let action = inFlight else { return }
        inFlight = nil
        switch action {
        case .acquire:
            status = .inactive; restoration = .verified
            retryAt = now + Self.unavailableRetrySeconds
            unavailableReason = "helperUnavailable"
        case .renew:
            break   // `next` marks the lease lost once the window passes without an acknowledgement
        case .release:
            status = .releaseFailed("helperUnavailable"); restoration = .failed
            retryAt = now + Self.releaseRetrySeconds
        }
    }

    private static func restoration(afterStop reply: HoldReply) -> RestoreState {
        switch reply.state {
        case "restored", "stopped", "ready": .verified
        case "cleanupAcknowledged": .pending
        case "recoveryRequired": reply.reason.hasPrefix("foreign") ? .conflict : .failed
        default: .unknown
        }
    }
}

/// Performs a `HoldAction` against the helper. `nil` means the call did not reach it.
public protocol PowerHoldTransport: Sendable {
    func send(_ action: HoldAction) async -> HoldReply?
    func close()
}
