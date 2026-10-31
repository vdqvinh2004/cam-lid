import Foundation
import CoreFoundation

/// Validated preferences. Ranges/defaults from T004 + domain-model.md.
/// Updates apply atomically: the whole patch validates before anything changes.
/// Unknown keys are rejected. Migration preserves hard floors/caps and never arms.
public struct Configuration: Sendable, Codable, Equatable {
    public static let schemaVersion = 1

    public var mode: RequestedMode
    public var closedLidOptIn: Bool
    public var completionDelayMinutes: Int
    public var waitRetentionMinutes: Int
    public var batteryFloorPercent: Int
    public var chargingOnly: Bool
    public var batteryModeAllowed: Bool
    public var batteryEntryPercent: Int
    public var batteryCapMinutes: Int
    public var runCapMinutes: Int
    /// Separate from mode so the Timed choice survives using Auto. Zero is Infinite.
    public var timerMinutes: Int?
    public var cpuStopEnabled: Bool
    /// Missing in older preferences means display sleep is allowed. Preview does not actuate power.
    public var allowDisplaySleep: Bool?
    public var displaySleepAllowed: Bool { allowDisplaySleep ?? true }
    public var adapterEnrollment: [String]
    /// Retained for preference/CLI compatibility; Detect Orca now owns source enablement.
    public var orcaMetadataConsent: Bool?
    public var orcaMetadataAllowed: Bool { adapterEnrollment.contains("orca") }
    public var launchAtLogin: Bool
    public var notificationCategories: [NotificationCategory]?
    /// Missing for older preference files means no lifetime rules.
    public var lifetimeRules: [LifetimeRule]?
    public var telemetryEnabled: Bool
    /// Missing for older preference files means Standard.
    public var powerMode: PowerMode

    public init(
        mode: RequestedMode = .off,
        closedLidOptIn: Bool = false,
        completionDelayMinutes: Int = 2,
        waitRetentionMinutes: Int = 5,
        batteryFloorPercent: Int = 20,
        chargingOnly: Bool = true,
        batteryModeAllowed: Bool = false,
        batteryEntryPercent: Int? = nil,
        batteryCapMinutes: Int = 60,
        runCapMinutes: Int = 120,
        timerMinutes: Int? = nil,
        cpuStopEnabled: Bool = false,
        allowDisplaySleep: Bool? = nil,
        adapterEnrollment: [String] = [],
        orcaMetadataConsent: Bool? = nil,
        launchAtLogin: Bool = false,
        notificationCategories: [NotificationCategory]? = nil,
        lifetimeRules: [LifetimeRule]? = nil,
        telemetryEnabled: Bool = false,
        powerMode: PowerMode = .standard
    ) throws(ConfigError) {
        self.mode = mode
        self.closedLidOptIn = closedLidOptIn
        self.completionDelayMinutes = completionDelayMinutes
        self.waitRetentionMinutes = waitRetentionMinutes
        self.batteryFloorPercent = batteryFloorPercent
        self.chargingOnly = chargingOnly
        self.batteryModeAllowed = batteryModeAllowed
        self.batteryEntryPercent = batteryEntryPercent ?? max(40, min(50, batteryFloorPercent) + 1)
        self.batteryCapMinutes = batteryCapMinutes
        self.runCapMinutes = runCapMinutes
        self.timerMinutes = timerMinutes
        self.cpuStopEnabled = cpuStopEnabled
        self.allowDisplaySleep = allowDisplaySleep
        self.adapterEnrollment = adapterEnrollment
        self.orcaMetadataConsent = orcaMetadataConsent
        self.launchAtLogin = launchAtLogin
        self.notificationCategories = notificationCategories
        self.lifetimeRules = lifetimeRules
        self.telemetryEnabled = telemetryEnabled
        self.powerMode = powerMode
        try validate()
    }

    public func validate() throws(ConfigError) {
        try checkRange("completionDelayMinutes", completionDelayMinutes, 0...30)
        try checkRange("waitRetentionMinutes", waitRetentionMinutes, 0...30)
        try checkRange("batteryFloorPercent", batteryFloorPercent, 10...50)
        try checkRange("batteryEntryPercent", batteryEntryPercent, 20...80)
        try checkRange("batteryCapMinutes", batteryCapMinutes, 15...240)
        guard batteryEntryPercent > batteryFloorPercent else {
            throw .outOfRange(field: "batteryEntryPercent", value: batteryEntryPercent, allowed: "\(max(20, batteryFloorPercent + 1))...80")
        }
        try checkRange("runCapMinutes", runCapMinutes, 5...480)
        if let timerMinutes, timerMinutes != 0 { try checkRange("timerMinutes", timerMinutes, 5...480) }
        guard adapterEnrollment.count <= PolicyLimits.maxEnrolledTasks else {
            throw ConfigError.outOfRange(field: "adapterEnrollment", value: adapterEnrollment.count, allowed: "0...20")
        }
        if let categories = notificationCategories,
           categories.count > 4 || Set(categories).count != categories.count {
            throw ConfigError.invalidType(key: "notificationCategories")
        }
        if let lifetimeRules {
            do { try LifetimeRule.validateCollection(lifetimeRules) }
            catch ValidationError.outOfRange {
                throw ConfigError.outOfRange(field: "lifetimeRules", value: lifetimeRules.count, allowed: "0...20")
            } catch {
                throw ConfigError.invalidType(key: "lifetimeRules")
            }
        }
        for adapter in adapterEnrollment {
            do { try validateString(adapter) } catch {
                throw ConfigError.stringTooLong(adapter.count)
            }
        }
    }

    /// Atomic partial patch: returns the new config or throws, never half-applied.
    public func applying(_ patch: ConfigPatch) throws(ConfigError) -> Configuration {
        var next = self
        if let mode = patch.mode { next.mode = mode }
        if let optIn = patch.closedLidOptIn { next.closedLidOptIn = optIn }
        if let value = patch.completionDelayMinutes { next.completionDelayMinutes = value }
        if let value = patch.waitRetentionMinutes { next.waitRetentionMinutes = value }
        if let value = patch.batteryFloorPercent { next.batteryFloorPercent = value }
        if let value = patch.chargingOnly { next.chargingOnly = value }
        if let value = patch.batteryModeAllowed { next.batteryModeAllowed = value }
        if let value = patch.batteryEntryPercent { next.batteryEntryPercent = value }
        if let value = patch.batteryCapMinutes { next.batteryCapMinutes = value }
        if let value = patch.runCapMinutes { next.runCapMinutes = value }
        if let value = patch.timerMinutes { next.timerMinutes = value }
        if let value = patch.cpuStopEnabled { next.cpuStopEnabled = value }
        if let value = patch.allowDisplaySleep { next.allowDisplaySleep = value }
        if let value = patch.adapterEnrollment { next.adapterEnrollment = value }
        if let value = patch.orcaMetadataConsent { next.orcaMetadataConsent = value }
        if let value = patch.launchAtLogin { next.launchAtLogin = value }
        if let value = patch.notificationCategories { next.notificationCategories = value }
        if let value = patch.lifetimeRules { next.lifetimeRules = value }
        if let value = patch.telemetryEnabled { next.telemetryEnabled = value }
        if let value = patch.powerMode { next.powerMode = value }
        try next.validate()
        return next
    }

    /// Schema migration: known keys carried (clamped to hard bounds), removed keys
    /// reset to defaults, protection never armed as a side effect of upgrade.
    public static func migrate(from dictionary: [String: Any]) throws(ConfigError) -> Configuration {
        var next = try Configuration()
        func clamped(_ key: String, _ value: Int, _ range: ClosedRange<Int>) -> Int {
            _ = key
            return min(max(value, range.lowerBound), range.upperBound)
        }
        if let value = dictionary["completionDelayMinutes"] as? Int {
            next.completionDelayMinutes = clamped("completionDelayMinutes", value, 0...30)
        }
        if let value = dictionary["waitRetentionMinutes"] as? Int {
            next.waitRetentionMinutes = clamped("waitRetentionMinutes", value, 0...30)
        }
        if let value = dictionary["batteryFloorPercent"] as? Int {
            next.batteryFloorPercent = clamped("batteryFloorPercent", value, 10...50)
        }
        if let value = dictionary["runCapMinutes"] as? Int {
            next.runCapMinutes = clamped("runCapMinutes", value, 5...480)
        }
        if let value = dictionary["timerMinutes"] as? Int {
            next.timerMinutes = value == 0 ? 0 : clamped("timerMinutes", value, 5...480)
        }
        if let value = dictionary["chargingOnly"] as? Bool { next.chargingOnly = value }
        if let raw = dictionary["batteryModeAllowed"] {
            next.batteryModeAllowed = try ConfigPatch(jsonDictionary: ["batteryModeAllowed": raw]).batteryModeAllowed ?? false
        }
        next.batteryEntryPercent = max(40, next.batteryFloorPercent + 1)
        if let raw = dictionary["batteryEntryPercent"] {
            let value = try ConfigPatch(jsonDictionary: ["batteryEntryPercent": raw]).batteryEntryPercent ?? 40
            next.batteryEntryPercent = max(next.batteryFloorPercent + 1, min(max(value, 20), 80))
        }
        if let raw = dictionary["batteryCapMinutes"] {
            let value = try ConfigPatch(jsonDictionary: ["batteryCapMinutes": raw]).batteryCapMinutes ?? 60
            next.batteryCapMinutes = min(max(value, 15), 240)
        }
        if let value = dictionary["cpuStopEnabled"] as? Bool { next.cpuStopEnabled = value }
        if let value = dictionary["allowDisplaySleep"] as? Bool { next.allowDisplaySleep = value }
        if let value = dictionary["launchAtLogin"] as? Bool { next.launchAtLogin = value }
        if let categories = dictionary["notificationCategories"] {
            next.notificationCategories = try ConfigPatch(jsonDictionary: ["notificationCategories": categories]).notificationCategories
        }
        if let rules = dictionary["lifetimeRules"] {
            next.lifetimeRules = try ConfigPatch(jsonDictionary: ["lifetimeRules": rules]).lifetimeRules
        }
        if let value = dictionary["telemetryEnabled"] as? Bool { next.telemetryEnabled = value }
        if let value = dictionary["orcaMetadataConsent"] as? Bool { next.orcaMetadataConsent = value }
        if let value = (dictionary["powerMode"] as? String).flatMap(PowerMode.init(rawValue:)) { next.powerMode = value }
        // Never silently arm after upgrade, regardless of stored values.
        next.mode = .off
        next.closedLidOptIn = false
        try next.validate()
        return next
    }

    public var timedDurationMinutes: Int {
        timerMinutes ?? (mode == .manual ? 0 : runCapMinutes)
    }

    /// Finite sessions retain the hard cap. Infinite only bypasses time expiry.
    public func sessionDurationMinutes(for mode: RequestedMode, powerSource: PowerSource = .ac) -> Int? {
        let duration: Int? = mode == .manual || (mode == .timed && timedDurationMinutes == 0)
            ? nil : (mode == .timed ? min(timedDurationMinutes, runCapMinutes) : runCapMinutes)
        guard powerSource != .ac else { return duration }
        return min(duration ?? runCapMinutes, runCapMinutes, batteryCapMinutes)
    }

    /// Entry uses fresh health, not the throttled monitoring safety signal.
    public func batteryEntryRefusal(health: HealthSnapshot) -> String? {
        guard health.powerSource != .ac else { return nil }
        guard health.powerSource == .battery else { return "powerUnknown" }
        guard !chargingOnly, batteryModeAllowed else { return "notCharging" }
        guard let battery = health.batteryPercent else { return "batteryUnknown" }
        return battery < Double(batteryEntryPercent) ? "batteryEntryLow" : nil
    }

    private enum CodingKeys: String, CodingKey {
        case mode, closedLidOptIn, completionDelayMinutes, waitRetentionMinutes
        case batteryFloorPercent, chargingOnly, batteryModeAllowed, batteryEntryPercent, batteryCapMinutes
        case runCapMinutes, timerMinutes, cpuStopEnabled, allowDisplaySleep, adapterEnrollment
        case orcaMetadataConsent, launchAtLogin, notificationCategories, lifetimeRules, telemetryEnabled, powerMode
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(RequestedMode.self, forKey: .mode)
        closedLidOptIn = try values.decode(Bool.self, forKey: .closedLidOptIn)
        completionDelayMinutes = try values.decode(Int.self, forKey: .completionDelayMinutes)
        waitRetentionMinutes = try values.decode(Int.self, forKey: .waitRetentionMinutes)
        batteryFloorPercent = try values.decode(Int.self, forKey: .batteryFloorPercent)
        chargingOnly = try values.decode(Bool.self, forKey: .chargingOnly)
        batteryModeAllowed = try values.decodeIfPresent(Bool.self, forKey: .batteryModeAllowed) ?? false
        batteryEntryPercent = try values.decodeIfPresent(Int.self, forKey: .batteryEntryPercent) ?? max(40, min(50, batteryFloorPercent) + 1)
        batteryCapMinutes = try values.decodeIfPresent(Int.self, forKey: .batteryCapMinutes) ?? 60
        runCapMinutes = try values.decode(Int.self, forKey: .runCapMinutes)
        timerMinutes = try values.decodeIfPresent(Int.self, forKey: .timerMinutes)
        cpuStopEnabled = try values.decode(Bool.self, forKey: .cpuStopEnabled)
        allowDisplaySleep = try values.decodeIfPresent(Bool.self, forKey: .allowDisplaySleep)
        adapterEnrollment = try values.decode([String].self, forKey: .adapterEnrollment)
        orcaMetadataConsent = try values.decodeIfPresent(Bool.self, forKey: .orcaMetadataConsent)
        launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
        notificationCategories = try values.decodeIfPresent([NotificationCategory].self, forKey: .notificationCategories)
        lifetimeRules = try values.decodeIfPresent([LifetimeRule].self, forKey: .lifetimeRules)
        telemetryEnabled = try values.decode(Bool.self, forKey: .telemetryEnabled)
        powerMode = try values.decodeIfPresent(PowerMode.self, forKey: .powerMode) ?? .standard
    }
}

private func checkRange(_ field: String, _ value: Int, _ range: ClosedRange<Int>) throws(ConfigError) {
    guard range.contains(value) else {
        throw .outOfRange(field: field, value: value, allowed: "\(range.lowerBound)...\(range.upperBound)")
    }
}

private func unknownKeysRemoved(_ dictionary: [String: Any]) -> Set<String> {
    let known: Set<String> = [
        "mode", "closedLidOptIn", "completionDelayMinutes", "waitRetentionMinutes",
        "batteryFloorPercent", "chargingOnly", "batteryModeAllowed", "batteryEntryPercent", "batteryCapMinutes", "runCapMinutes", "timerMinutes", "cpuStopEnabled", "allowDisplaySleep",
        "adapterEnrollment", "orcaMetadataConsent", "launchAtLogin", "notificationCategories", "lifetimeRules", "telemetryEnabled", "powerMode", "schemaVersion",
    ]
    return Set(dictionary.keys).subtracting(known)
}

public struct ConfigPatch: Codable, Sendable, Equatable {
    public var mode: RequestedMode?
    public var closedLidOptIn: Bool?
    public var completionDelayMinutes: Int?
    public var waitRetentionMinutes: Int?
    public var batteryFloorPercent: Int?
    public var chargingOnly: Bool?
    public var batteryModeAllowed: Bool?
    public var batteryEntryPercent: Int?
    public var batteryCapMinutes: Int?
    public var runCapMinutes: Int?
    public var timerMinutes: Int?
    public var allowDisplaySleep: Bool?
    public var cpuStopEnabled: Bool?
    public var adapterEnrollment: [String]?
    public var orcaMetadataConsent: Bool?
    public var notificationCategories: [NotificationCategory]?
    public var lifetimeRules: [LifetimeRule]?
    public var launchAtLogin: Bool?
    public var telemetryEnabled: Bool?
    public var powerMode: PowerMode?

    public init() {}

    /// Dictionary patch (e.g. from `config set --file`): unknown keys rejected,
    /// and present known keys with the wrong type (including null where
    /// unsupported) are rejected instead of silently ignored.
    public init(jsonDictionary: [String: Any]) throws(ConfigError) {
        self.init()
        let unknown = unknownKeysRemoved(jsonDictionary)
        guard unknown.isEmpty else { throw .unknownKeys(Array(unknown).sorted()) }
        if let raw = jsonDictionary["orcaMetadataConsent"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else {
                throw .invalidType(key: "orcaMetadataConsent")
            }
            orcaMetadataConsent = value
        }
        if let raw = jsonDictionary["powerMode"] {
            guard let string = raw as? String, let value = PowerMode(rawValue: string) else { throw .invalidType(key: "powerMode") }
            powerMode = value
        }
        if let raw = jsonDictionary["mode"] {
            guard let string = raw as? String else { throw .invalidType(key: "mode") }
            guard let mode = RequestedMode(rawValue: string) else {
                throw .invalidMode(string)
            }
            self.mode = mode
        }
        if let raw = jsonDictionary["closedLidOptIn"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "closedLidOptIn") }
            self.closedLidOptIn = value
        }
        if let raw = jsonDictionary["completionDelayMinutes"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else {
                throw .invalidType(key: "completionDelayMinutes")
            }
            self.completionDelayMinutes = value
        }
        if let raw = jsonDictionary["waitRetentionMinutes"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else {
                throw .invalidType(key: "waitRetentionMinutes")
            }
            self.waitRetentionMinutes = value
        }
        if let raw = jsonDictionary["batteryFloorPercent"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else {
                throw .invalidType(key: "batteryFloorPercent")
            }
            self.batteryFloorPercent = value
        }
        if let raw = jsonDictionary["chargingOnly"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "chargingOnly") }
            self.chargingOnly = value
        }
        if let raw = jsonDictionary["batteryModeAllowed"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "batteryModeAllowed") }
            self.batteryModeAllowed = value
        }
        if let raw = jsonDictionary["batteryEntryPercent"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else { throw .invalidType(key: "batteryEntryPercent") }
            self.batteryEntryPercent = value
        }
        if let raw = jsonDictionary["batteryCapMinutes"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else { throw .invalidType(key: "batteryCapMinutes") }
            self.batteryCapMinutes = value
        }
        if let raw = jsonDictionary["runCapMinutes"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else { throw .invalidType(key: "runCapMinutes") }
            self.runCapMinutes = value
        }
        if let raw = jsonDictionary["timerMinutes"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let value = raw as? Int else { throw .invalidType(key: "timerMinutes") }
            self.timerMinutes = value
        }
        if let raw = jsonDictionary["allowDisplaySleep"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "allowDisplaySleep") }
            self.allowDisplaySleep = value
        }
        if let raw = jsonDictionary["cpuStopEnabled"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "cpuStopEnabled") }
            self.cpuStopEnabled = value
        }
        if let raw = jsonDictionary["adapterEnrollment"] {
            guard let value = raw as? [String] else {
                throw .invalidType(key: "adapterEnrollment")
            }
            self.adapterEnrollment = value
        }
        if let raw = jsonDictionary["notificationCategories"] {
            guard let values = raw as? [String], values.count <= 4,
                  Set(values).count == values.count,
                  values.allSatisfy({ NotificationCategory(rawValue: $0) != nil }) else {
                throw .invalidType(key: "notificationCategories")
            }
            self.notificationCategories = values.compactMap(NotificationCategory.init(rawValue:))
        }
        if let raw = jsonDictionary["lifetimeRules"] {
            do {
                let data = try JSONSerialization.data(withJSONObject: raw)
                let rules = try JSONDecoder().decode([LifetimeRule].self, from: data)
                try LifetimeRule.validateCollection(rules)
                self.lifetimeRules = rules
            } catch {
                throw .invalidType(key: "lifetimeRules")
            }
        }
        if let raw = jsonDictionary["launchAtLogin"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "launchAtLogin") }
            self.launchAtLogin = value
        }
        if let raw = jsonDictionary["telemetryEnabled"] {
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), let value = raw as? Bool else { throw .invalidType(key: "telemetryEnabled") }
            self.telemetryEnabled = value
        }
    }
}

public enum ConfigError: Error, Equatable, Sendable {
    case outOfRange(field: String, value: Int, allowed: String)
    case unknownKeys([String])
    case invalidMode(String)
    case invalidType(key: String)
    case stringTooLong(Int)
}
