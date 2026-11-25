import CamLidPowerWire

/// Bounded safety stop policy. Unknown is not healthy: any missing safety input
/// stops protection with a specific reason. Feeds PolicyEngine as SafetySignal.
/// Thermal follows ThermalGuard, the rule the helper also uses; 5s sampling, 15s stale stop,
/// battery/AC cutoff, latched re-arm (latch lives in the engine).
public struct SafetyPolicy: Sendable {
    public static let seriousThermalSeconds = ThermalGuard.seriousGraceSeconds
    public static let sampleIntervalSeconds = 5.0

    private var thermal = ThermalGuard()
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

        if let stop = thermal.stopReason(for: ThermalLevel(health.thermalPressure), now: now) {
            reasons.append(stop)
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

extension ThermalLevel {
    /// The app's thermal reading as the shared guard reads it.
    init(_ pressure: ThermalPressure) {
        switch pressure {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        case .unknown: self = .unknown
        }
    }
}
