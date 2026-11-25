/// Thermal pressure as the closed-lid guards read it. The app's safety policy and the root helper both use it, so a
/// thermal stop means the same thing on both sides of the wire.
public enum ThermalLevel: String, Codable, Sendable, CaseIterable {
    case nominal, fair, serious, critical, unknown
}

/// The closed-lid thermal rule, shared by the app's safety policy and the helper. Fair is acceptable. Serious stops
/// protection only after it has lasted `seriousGraceSeconds` without a break. Critical and unknown stop at once.
/// Feed one reading per evaluation, with monotonic seconds.
public struct ThermalGuard: Sendable {
    public static let seriousGraceSeconds = 30.0
    private var seriousSince: Double?

    public init() {}

    /// The stop reason for `level` at `now`, or nil while protection may continue.
    public mutating func stopReason(for level: ThermalLevel, now: Double) -> String? {
        switch level {
        case .nominal, .fair:
            seriousSince = nil
            return nil
        case .serious:
            if seriousSince == nil { seriousSince = now }
            guard let start = seriousSince, now - start >= Self.seriousGraceSeconds else { return nil }
            return "thermalSerious"
        case .critical:
            // The serious clock is kept: a return to serious after critical does not restart the grace.
            return "thermalCritical"
        case .unknown:
            seriousSince = nil
            return "thermalUnknown"
        }
    }
}
