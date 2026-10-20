/// Sensor readings with a monotonic measurement timestamp. Real IOKit telemetry
/// arrives through this shape later; tests and the simulator inject fakes.
/// T009 (shared half): freshness rule lives here, stop policy in SafetyPolicy.
public struct SensorReadings: Sendable, Equatable {
    public var lidObservation: LidObservation?
    public var temperature: TemperatureObservation
    public var criticalThermalSampledAtMonotonic: Double?
    public var batteryPercent: Double?
    public var powerSource: PowerSource
    public var thermalPressure: ThermalPressure
    public var cpuPercent: Double?
    public var lidState: LidState
    public var internalDisplayState: DisplayState
    public var measuredAtMonotonic: Double

    public init(
        batteryPercent: Double? = nil, powerSource: PowerSource = .unknown,
        thermalPressure: ThermalPressure = .unknown, cpuPercent: Double? = nil,
        lidState: LidState = .unknown, internalDisplayState: DisplayState = .unknown,
        measuredAtMonotonic: Double = 0, lidObservation: LidObservation? = nil, temperature: TemperatureObservation = .unsupported,
        criticalThermalSampledAtMonotonic: Double? = nil
    ) {
        self.lidObservation = lidObservation
        self.temperature = temperature
        self.criticalThermalSampledAtMonotonic = criticalThermalSampledAtMonotonic
        self.batteryPercent = batteryPercent
        self.powerSource = powerSource
        self.thermalPressure = thermalPressure
        self.cpuPercent = cpuPercent
        self.lidState = lidState
        self.internalDisplayState = internalDisplayState
        self.measuredAtMonotonic = measuredAtMonotonic
    }
}

public protocol SensorProvider: Sendable {
    func read() -> SensorReadings
}

public struct HealthMonitor: Sendable {
    /// Measurements older than this are stale: reported as unknown, never as
    /// last-known-good. 15s per FR-010/SafetyPolicy contract.
    public static let staleAfterSeconds = 15.0

    public init() {}

    /// Converts raw readings to a validated snapshot. Invalid percentages become
    /// missing (never zero); stale readings become unknown. Never throws: every
    /// degradation is reported in `issues` instead.
    public func snapshot(from readings: SensorReadings, now: Double) -> (
        snapshot: HealthSnapshot, issues: [String]
    ) {
        if !now.isFinite || !readings.measuredAtMonotonic.isFinite || readings.measuredAtMonotonic < 0 || now < readings.measuredAtMonotonic || now - readings.measuredAtMonotonic > Self.staleAfterSeconds {
            let freshCritical = readings.thermalPressure == .critical && readings.criticalThermalSampledAtMonotonic.map {
                $0.isFinite && $0 >= 0 && now.isFinite && now >= $0 && now - $0 <= 1
            } == true
            let snapshot = try! HealthSnapshot(thermalPressure: freshCritical ? .critical : .unknown,
                lid: readings.lidObservation?.projected(now: now), temperature: readings.temperature.projected(now: now))
            return (snapshot, ["staleTelemetry"])
        }
        var issues: [String] = []
        var battery = readings.batteryPercent
        if let value = battery, (try? validatePercent(value, field: "battery")) == nil {
            battery = nil
            issues.append("batteryInvalid")
        }
        var cpu = readings.cpuPercent
        if let value = cpu, (try? validatePercent(value, field: "cpu")) == nil {
            cpu = nil
            issues.append("cpuInvalid")
        }
        // Bounds already enforced above; force-unwrap cannot fail.
        let snapshot = try! HealthSnapshot(
            batteryPercent: battery, powerSource: readings.powerSource,
            thermalPressure: readings.thermalPressure, cpuPercent: cpu,
            lidState: readings.lidObservation?.projected(now: now).state ?? readings.lidState, internalDisplayState: readings.internalDisplayState,
            capabilityVerified: false, lid: readings.lidObservation?.projected(now: now), temperature: readings.temperature.projected(now: now)
        )
        return (snapshot, issues)
    }
}
