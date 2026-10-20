import Foundation
import CamLidCore

/// Acceptance-fixture schema (F13). The committed fixtures live in
/// `Tests/Contracts/Fixtures/*.json` with envelope
/// `{fixture, description, config, steps[]}` plus optional `capDeadlineAt`.
///
/// `sensors.battery: null` decodes to explicit-missing (unknown telemetry),
/// distinct from an absent `battery` key which defaults to healthy. The same
/// absent-vs-null distinction applies to every sensor field.
public struct FixtureFile: Sendable, Decodable, Equatable {
    public var fixture: String
    public var fixtureDescription: String
    public var config: FixtureConfig
    public var steps: [FixtureStep]
    public var capDeadlineAt: Double?

    enum CodingKeys: String, CodingKey {
        case fixture
        case description
        case config
        case steps
        case capDeadlineAt
    }

    public init(
        fixture: String, description: String, config: FixtureConfig,
        steps: [FixtureStep], capDeadlineAt: Double? = nil
    ) {
        self.fixture = fixture
        self.fixtureDescription = description
        self.config = config
        self.steps = steps
        self.capDeadlineAt = capDeadlineAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fixture = try container.decode(String.self, forKey: .fixture)
        fixtureDescription = try container.decode(String.self, forKey: .description)
        config = try container.decode(FixtureConfig.self, forKey: .config)
        steps = try container.decode([FixtureStep].self, forKey: .steps)
        capDeadlineAt = try container.decodeIfPresent(Double.self, forKey: .capDeadlineAt)
    }
}

public struct FixtureConfig: Sendable, Decodable, Equatable {
    public var completionDelayMinutes: Int
    public var waitRetentionMinutes: Int
    public var batteryFloorPercent: Int
    public var runCapMinutes: Int

    public init(
        completionDelayMinutes: Int = 2, waitRetentionMinutes: Int = 5,
        batteryFloorPercent: Int = 20, runCapMinutes: Int = 120
    ) {
        self.completionDelayMinutes = completionDelayMinutes
        self.waitRetentionMinutes = waitRetentionMinutes
        self.batteryFloorPercent = batteryFloorPercent
        self.runCapMinutes = runCapMinutes
    }

    public func makeConfiguration() throws -> Configuration {
        try Configuration(
            completionDelayMinutes: completionDelayMinutes,
            waitRetentionMinutes: waitRetentionMinutes,
            batteryFloorPercent: batteryFloorPercent,
            runCapMinutes: runCapMinutes)
    }
}

public struct FixtureTask: Sendable, Decodable, Equatable {
    public var id: String
    public var state: String
    public var kind: String
    public var waitUntil: Double?
    public var unknownUntil: Double?

    public init(
        id: String, state: String, kind: String,
        waitUntil: Double? = nil, unknownUntil: Double? = nil
    ) {
        self.id = id
        self.state = state
        self.kind = kind
        self.waitUntil = waitUntil
        self.unknownUntil = unknownUntil
    }
}

public struct FixtureSensors: Sendable, Equatable, Decodable {
    public var battery: Double?
    public var batteryPresent: Bool
    public var power: String?
    public var powerPresent: Bool
    public var thermal: String?
    public var thermalPresent: Bool
    public var lid: String?
    public var lidPresent: Bool
    public var display: String?
    public var displayPresent: Bool
    public var cpu: Double?
    public var cpuPresent: Bool

    public init(
        battery: Double? = nil, batteryPresent: Bool = false,
        power: String? = nil, powerPresent: Bool = false,
        thermal: String? = nil, thermalPresent: Bool = false,
        lid: String? = nil, lidPresent: Bool = false,
        display: String? = nil, displayPresent: Bool = false,
        cpu: Double? = nil, cpuPresent: Bool = false
    ) {
        self.battery = battery
        self.batteryPresent = batteryPresent
        self.power = power
        self.powerPresent = powerPresent
        self.thermal = thermal
        self.thermalPresent = thermalPresent
        self.lid = lid
        self.lidPresent = lidPresent
        self.display = display
        self.displayPresent = displayPresent
        self.cpu = cpu
        self.cpuPresent = cpuPresent
    }

    enum CodingKeys: String, CodingKey {
        case battery, power, thermal, lid, display, cpu
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Battery: absent -> healthy default; null -> explicit missing; number -> value.
        if container.contains(.battery) {
            batteryPresent = true
            if try container.decodeNil(forKey: .battery) {
                battery = nil
            } else {
                battery = try container.decode(Double.self, forKey: .battery)
            }
        } else {
            batteryPresent = false
            battery = nil
        }
        if container.contains(.power) {
            powerPresent = true
            if try container.decodeNil(forKey: .power) {
                power = nil
            } else {
                power = try container.decode(String.self, forKey: .power)
            }
        } else {
            powerPresent = false
            power = nil
        }
        if container.contains(.thermal) {
            thermalPresent = true
            if try container.decodeNil(forKey: .thermal) {
                thermal = nil
            } else {
                thermal = try container.decode(String.self, forKey: .thermal)
            }
        } else {
            thermalPresent = false
            thermal = nil
        }
        if container.contains(.lid) {
            lidPresent = true
            if try container.decodeNil(forKey: .lid) {
                lid = nil
            } else {
                lid = try container.decode(String.self, forKey: .lid)
            }
        } else {
            lidPresent = false
            lid = nil
        }
        if container.contains(.display) {
            displayPresent = true
            if try container.decodeNil(forKey: .display) {
                display = nil
            } else {
                display = try container.decode(String.self, forKey: .display)
            }
        } else {
            displayPresent = false
            display = nil
        }
        if container.contains(.cpu) {
            cpuPresent = true
            if try container.decodeNil(forKey: .cpu) {
                cpu = nil
            } else {
                cpu = try container.decode(Double.self, forKey: .cpu)
            }
        } else {
            cpuPresent = false
            cpu = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if batteryPresent {
            if let value = battery {
                try container.encode(value, forKey: .battery)
            } else {
                try container.encodeNil(forKey: .battery)
            }
        }
        if powerPresent {
            if let value = power {
                try container.encode(value, forKey: .power)
            } else {
                try container.encodeNil(forKey: .power)
            }
        }
        if thermalPresent {
            if let value = thermal {
                try container.encode(value, forKey: .thermal)
            } else {
                try container.encodeNil(forKey: .thermal)
            }
        }
        if lidPresent {
            if let value = lid {
                try container.encode(value, forKey: .lid)
            } else {
                try container.encodeNil(forKey: .lid)
            }
        }
        if displayPresent {
            if let value = display {
                try container.encode(value, forKey: .display)
            } else {
                try container.encodeNil(forKey: .display)
            }
        }
        if cpuPresent {
            if let value = cpu {
                try container.encode(value, forKey: .cpu)
            } else {
                try container.encodeNil(forKey: .cpu)
            }
        }
    }

    static func parsePower(_ raw: String?) -> PowerSource {
        guard let raw else { return .unknown }
        return PowerSource(rawValue: raw) ?? .unknown
    }

    static func parseThermal(_ raw: String?) -> ThermalPressure {
        guard let raw else { return .unknown }
        return ThermalPressure(rawValue: raw) ?? .unknown
    }

    static func parseLid(_ raw: String?) -> LidState {
        guard let raw else { return .unknown }
        return LidState(rawValue: raw) ?? .unknown
    }

    static func parseDisplay(_ raw: String?) -> DisplayState {
        guard let raw else { return .unknown }
        return DisplayState(rawValue: raw) ?? .unknown
    }

    /// Absent keys default to healthy (AC/nominal/open/awake/80%/10%).
    /// Present-null decodes to explicit missing (nil / .unknown), never healthy.
    public func sensorReadings(at: Double) -> SensorReadings {
        let batteryValue: Double?
        if !batteryPresent {
            batteryValue = 80
        } else {
            batteryValue = battery
        }
        let powerValue: PowerSource
        if !powerPresent {
            powerValue = .ac
        } else {
            powerValue = Self.parsePower(power)
        }
        let thermalValue: ThermalPressure
        if !thermalPresent {
            thermalValue = .nominal
        } else {
            thermalValue = Self.parseThermal(thermal)
        }
        let lidValue: LidState
        if !lidPresent {
            lidValue = .open
        } else {
            lidValue = Self.parseLid(lid)
        }
        let displayValue: DisplayState
        if !displayPresent {
            displayValue = .awake
        } else {
            displayValue = Self.parseDisplay(display)
        }
        let cpuValue: Double?
        if !cpuPresent {
            cpuValue = 10
        } else {
            cpuValue = cpu
        }
        return SensorReadings(
            batteryPercent: batteryValue, powerSource: powerValue,
            thermalPressure: thermalValue, cpuPercent: cpuValue,
            lidState: lidValue, internalDisplayState: displayValue,
            measuredAtMonotonic: at)
    }
}

public struct FixtureStep: Sendable, Decodable, Equatable {
    public var at: Double
    public var tasks: [FixtureTask]
    public var sensors: FixtureSensors
    public var safety: [String]
    public var expect: String
    public var expectReasons: [String]?

    enum CodingKeys: String, CodingKey {
        case at, tasks, sensors, safety, expect, expectReasons
    }

    public init(
        at: Double, tasks: [FixtureTask] = [], sensors: FixtureSensors = FixtureSensors(),
        safety: [String] = [], expect: String, expectReasons: [String]? = nil
    ) {
        self.at = at
        self.tasks = tasks
        self.sensors = sensors
        self.safety = safety
        self.expect = expect
        self.expectReasons = expectReasons
    }
}

/// `config-bounds.json` uses a different envelope (validation matrix, not
/// policy steps). Decoded separately so the "all five fixtures parse" check
/// covers every committed file without forcing one schema onto both shapes.
public struct ConfigBoundsFixture: Sendable, Decodable, Equatable {
    public var fixture: String
    public var description: String
    public var defaults: [String: IntCodable]
    public var validPatches: [[String: IntCodable]]
    public var invalidPatches: [InvalidPatchEntry]
    public var migration: MigrationEntry

    enum CodingKeys: String, CodingKey {
        case fixture, description, defaults, validPatches, invalidPatches, migration
    }

    public struct InvalidPatchEntry: Sendable, Decodable, Equatable {
        public var patch: [String: IntCodable]
        public var field: String?
        public var unknownKeys: [String]?

        enum CodingKeys: String, CodingKey {
            case patch, field, unknownKeys
        }
    }

    public struct MigrationEntry: Sendable, Decodable, Equatable {
        public var from: [String: JSONValue]
        public var expect: [String: JSONValue]
    }
}

/// Minimal JSON value retaining int/string/bool for the config-bounds matrix.
public enum IntCodable: Sendable, Decodable, Equatable {
    case int(Int)
    case bool(Bool)
    case string(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        let value = try container.decode(String.self)
        self = .string(value)
    }
}

public enum JSONValue: Sendable, Decodable, Equatable {
    case int(Int)
    case bool(Bool)
    case string(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        let value = try container.decode(String.self)
        self = .string(value)
    }
}

public enum FixtureLoader {
    public static func load(from data: Data) throws -> FixtureFile {
        try JSONDecoder().decode(FixtureFile.self, from: data)
    }

    public static func load(fromFile path: String, reader: any CLIFileReader) throws -> FixtureFile {
        let data = try reader.readFile(atPath: path)
        return try load(from: data)
    }

    public static func loadConfigBounds(from data: Data) throws -> ConfigBoundsFixture {
        try JSONDecoder().decode(ConfigBoundsFixture.self, from: data)
    }
}
