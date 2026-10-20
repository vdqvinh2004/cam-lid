/// Bounded safety stop policy. Unknown is not healthy: any missing safety input
/// stops protection with a specific reason. Feeds PolicyEngine as SafetySignal.
/// T011: serious thermal 30s, critical immediate, 5s sampling, 15s stale stop,
/// battery/AC cutoff, latched re-arm (latch lives in the engine).
public struct SafetyPolicy: Sendable {
    public static let seriousThermalSeconds = 30.0
    public static let sampleIntervalSeconds = 5.0

    private var seriousSince: Double?
    private var lastEvaluatedAt: Double?
    private var lastConfiguration: Configuration?
    private var cached: SafetySignal = .clear

    public init() {}

    public mutating func evaluate(
        health: HealthSnapshot, config: Configuration, cpuStop: Bool, now: Double
    ) -> SafetySignal {
        // Sample health every 5s, but apply changed safety preferences immediately.
        // Urgent critical thermal bypasses the throttle: a critical reading is
        // always evaluated immediately so a stop is never delayed by the cache.
        if health.thermalPressure != .critical, config == lastConfiguration,
            let last = lastEvaluatedAt, now - last < Self.sampleIntervalSeconds
        {
            return cached
        }
        lastEvaluatedAt = now
        lastConfiguration = config
        var reasons: [String] = []

        switch health.thermalPressure {
        case .critical:
            reasons.append("thermalCritical")
        case .serious:
            if seriousSince == nil { seriousSince = now }
            if let start = seriousSince, now - start >= Self.seriousThermalSeconds {
                reasons.append("thermalSerious")
            }
        case .nominal, .fair:
            seriousSince = nil
        case .unknown:
            seriousSince = nil
            reasons.append("thermalUnknown")
        }

        if health.lidState == .unknown { reasons.append("lidUnknown") }
        if health.powerSource == .unknown {
            reasons.append("powerUnknown")
        } else if health.powerSource != .ac, config.chargingOnly || !config.batteryModeAllowed {
            reasons.append("notCharging")
        }
        if let battery = health.batteryPercent {
            if battery < Double(config.batteryFloorPercent) { reasons.append("batteryFloor") }
        } else if health.powerSource != .ac {
            reasons.append("batteryUnknown")
        }
        if cpuStop { reasons.append("cpuStop") }

        cached = SafetySignal(reasons: reasons)
        return cached
    }
}
