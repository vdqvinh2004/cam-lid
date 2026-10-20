/// Normalized CPU advisory. CPU never proves task completion or thermal safety;
/// it is advisory only unless the user explicitly opts into CPU stop.
/// T010: 90% sustained 120s advisory, optional stop.
public struct CPUEvaluation: Sendable, Equatable {
    public var advisory: Bool
    public var stop: Bool
    public var reasons: [String]
}

public struct CPUObserver: Sendable {
    public static let sustainedThreshold = 90.0
    public static let sustainedSeconds = 120.0

    private var overSince: Double?

    public init() {}

    /// Feed one normalized 0–100 reading (nil/nonfinite = missing, never zero).
    /// Missing data clears the sustained timer: absence of evidence is not evidence.
    public mutating func evaluate(
        cpuPercent: Double?, cpuStopEnabled: Bool, now: Double
    ) -> CPUEvaluation {
        guard let cpu = cpuPercent, cpu.isFinite, (0...100).contains(cpu) else {
            overSince = nil
            return CPUEvaluation(advisory: false, stop: false, reasons: ["cpuUnknown"])
        }
        if cpu >= Self.sustainedThreshold {
            if overSince == nil { overSince = now }
        } else {
            overSince = nil
        }
        guard let start = overSince, now - start >= Self.sustainedSeconds else {
            return CPUEvaluation(advisory: false, stop: false, reasons: [])
        }
        if cpuStopEnabled {
            return CPUEvaluation(advisory: true, stop: true, reasons: ["cpuSustained", "cpuStop"])
        }
        return CPUEvaluation(advisory: true, stop: false, reasons: ["cpuSustained"])
    }
}
