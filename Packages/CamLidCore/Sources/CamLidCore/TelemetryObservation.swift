import Foundation

/// Read-only physical lid signal, separately timestamped from other telemetry.
public struct LidObservation: Codable, Sendable, Equatable {
    public let state: LidState
    public let source: String
    public let availability: String
    public let sampledAtMonotonic: Double?
    public let reasonCode: String?
    public init(state: LidState = .unknown, sampledAtMonotonic: Double? = nil,
                availability: String = "available", reasonCode: String? = nil) {
        let supportedAvailability = ["available", "error", "stale", "unsupported", "permissionRequired"].contains(availability)
        let validTime = sampledAtMonotonic.map { $0.isFinite && $0 >= 0 } ?? (availability != "available")
        let validReason = reasonCode.map { $0.count <= 128 && $0.rangeOfCharacter(from: .controlCharacters) == nil } ?? true
        let available = availability == "available" && state != .unknown && sampledAtMonotonic != nil
        let valid = supportedAvailability && validTime && validReason && (availability != "available" || available)
        self.state = valid && available ? state : .unknown
        source = "IOPMrootDomain.AppleClamshellState"
        self.sampledAtMonotonic = validTime ? sampledAtMonotonic : nil
        self.availability = valid ? availability : "error"
        self.reasonCode = valid ? reasonCode : "invalidLidObservation"
    }
    private enum CodingKeys: String, CodingKey { case state, source, availability, sampledAtMonotonic, reasonCode }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state); try c.encode(source, forKey: .source)
        try c.encode(availability, forKey: .availability); try c.encode(sampledAtMonotonic, forKey: .sampledAtMonotonic)
        try c.encode(reasonCode, forKey: .reasonCode)
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let state = try c.decode(LidState.self, forKey: .state)
        let source = try c.decode(String.self, forKey: .source)
        let availability = try c.decode(String.self, forKey: .availability)
        let time = try c.decodeIfPresent(Double.self, forKey: .sampledAtMonotonic)
        let reason = try c.decodeIfPresent(String.self, forKey: .reasonCode)
        guard source == "IOPMrootDomain.AppleClamshellState",
              ["available", "error", "stale", "unsupported", "permissionRequired"].contains(availability),
              time.map({ $0.isFinite && $0 >= 0 }) ?? true,
              reason.map({ $0.count <= 128 }) ?? true,
              availability != "available" || (state != .unknown && time != nil),
              availability == "available" || state == .unknown else {
            throw DecodingError.dataCorruptedError(forKey: .availability, in: c, debugDescription: "Invalid lid observation")
        }
        self.init(state: state, sampledAtMonotonic: time, availability: availability, reasonCode: reason)
    }
    public func projected(now: Double) -> LidObservation {
        guard availability == "available" else { return self }
        guard let sampledAtMonotonic, sampledAtMonotonic.isFinite, now.isFinite,
              sampledAtMonotonic >= 0, now >= sampledAtMonotonic else {
            return LidObservation(availability: "error", reasonCode: reasonCode ?? "missingOrInvalidTimestamp")
        }
        guard now - sampledAtMonotonic <= 5 else {
            return LidObservation(state: .unknown, sampledAtMonotonic: sampledAtMonotonic,
                availability: "stale", reasonCode: "staleLid")
        }
        return self
    }
}


/// A named numerical source is advisory and never substitutes for thermal pressure.
/// Unsupported hosts expose explicit nulls; no private source is assumed qualified.
public struct TemperatureObservation: Codable, Sendable, Equatable {
    public let valueCelsius: Double?
    public let sensorID: String?
    public let displayName: String?
    public let source: String?
    public let sampledAtMonotonic: Double?
    public let availability: String
    public let reasonCode: String?
    public static let unsupported = TemperatureObservation()

    public init(valueCelsius: Double? = nil, sensorID: String? = nil,
                displayName: String? = nil, source: String? = nil,
                sampledAtMonotonic: Double? = nil, availability: String = "unsupported",
                reasonCode: String? = "noQualifiedTemperatureSource") {
        let valid = Self.valid(valueCelsius, sensorID, displayName, source, sampledAtMonotonic, availability, reasonCode)
        self.valueCelsius = valid ? valueCelsius : nil
        self.sensorID = valid ? sensorID : nil; self.displayName = valid ? displayName : nil
        self.source = valid ? source : nil; self.sampledAtMonotonic = valid ? sampledAtMonotonic : nil
        self.availability = valid ? availability : "error"
        self.reasonCode = valid ? reasonCode : "invalidTemperatureObservation"
    }
    private static func valid(_ value: Double?, _ sensor: String?, _ name: String?, _ source: String?,
                              _ time: Double?, _ availability: String, _ reason: String?) -> Bool {
        guard ["available", "stale", "unsupported", "error", "permissionRequired", "notApplicable"].contains(availability),
              [sensor, name, source, reason].allSatisfy({ $0.map { !$0.isEmpty && $0.count <= 128 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) } ?? true }),
              time.map({ $0.isFinite && $0 >= 0 }) ?? true,
              value.map({ $0.isFinite && (-273.15...1_000).contains($0) }) ?? true else { return false }
        return availability == "available" ? value != nil && sensor != nil && name != nil && source != nil && time != nil : value == nil
    }
    private enum CodingKeys: String, CodingKey { case valueCelsius, sensorID, displayName, source, sampledAtMonotonic, availability, reasonCode }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decodeIfPresent(Double.self, forKey: .valueCelsius)
        let sensor = try c.decodeIfPresent(String.self, forKey: .sensorID)
        let name = try c.decodeIfPresent(String.self, forKey: .displayName)
        let source = try c.decodeIfPresent(String.self, forKey: .source)
        let time = try c.decodeIfPresent(Double.self, forKey: .sampledAtMonotonic)
        let availability = try c.decode(String.self, forKey: .availability)
        let reason = try c.decodeIfPresent(String.self, forKey: .reasonCode)
        guard Self.valid(value, sensor, name, source, time, availability, reason) else {
            throw DecodingError.dataCorruptedError(forKey: .availability, in: c, debugDescription: "Invalid temperature observation")
        }
        self.init(valueCelsius: value, sensorID: sensor, displayName: name, source: source, sampledAtMonotonic: time, availability: availability, reasonCode: reason)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(valueCelsius, forKey: .valueCelsius); try c.encode(sensorID, forKey: .sensorID)
        try c.encode(displayName, forKey: .displayName); try c.encode(source, forKey: .source)
        try c.encode(sampledAtMonotonic, forKey: .sampledAtMonotonic)
        try c.encode(availability, forKey: .availability); try c.encode(reasonCode, forKey: .reasonCode)
    }
    public func projected(now: Double) -> Self {
        guard availability == "available" else { return self }
        guard let time = sampledAtMonotonic, now.isFinite, now >= time else {
            return Self(availability: "error", reasonCode: "invalidTemperatureTimestamp")
        }
        guard now - time <= 10 else {
            return Self(sensorID: sensorID, displayName: displayName, source: source, sampledAtMonotonic: time, availability: "stale", reasonCode: "staleTemperature")
        }
        return self
    }
    public var displayText: String {
        switch availability {
        case "available": return "\(displayName ?? "Temperature") · \(valueCelsius.map { String(format: "%.1f°C", $0) } ?? "Unknown")"
        case "stale": return "Unavailable · reading is stale"
        case "permissionRequired": return "Unavailable · permission required"
        case "unsupported": return "Unavailable · no qualified sensor"
        case "notApplicable": return "Not applicable"
        default: return "Unavailable · sensor read failed"
        }
    }
}
