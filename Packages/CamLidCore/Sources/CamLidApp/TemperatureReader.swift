import CamLidCore
import CoreFoundation
import Darwin
import Foundation

/// Qualified numerical CPU-die source for this host family (Mac16,12/macOS 27).
///
/// Interface: IOHIDEventSystemClient thermal matching {PrimaryUsagePage 0xff00,
/// PrimaryUsage 5}, temperature event (type 15) float field. Entry points are
/// resolved at runtime (dlopen/dlsym); anything missing degrades to
/// `.unsupported` (L12 version-change residual). No privileges, no writes.
/// Quantity: hottest CPU die ("PMU tdie*") valid in (0, 125)°C — unpopulated
/// sensors read negative and are rejected; battery/NAND/ALS/composite entries
/// are never selected. Two independent menu-bar apps corroborate live silicon
/// temps on this host (their composites track a hotter point, ~8–11°C above
/// hottest-die; documented definitional offset). Load-tracking verified:
/// hottest die rises under CPU load and falls on cooldown; full enumeration
/// measures ~64ms, inside the 200ms off-main sensor budget.
public enum TemperatureReader {
    public static func read() -> TemperatureObservation {
        guard let sample = HIDThermalReader.hottestDieSample() else { return .unsupported }
        // ContinuousTime matches the LiveSensors/HealthMonitor clock domain.
        // systemUptime was used here before and diverged by accumulated sleep time,
        // permanently marking readings stale. Never mix sensor timestamp domains.
        return TemperatureObservation(
            valueCelsius: sample.value,
            sensorID: sample.sensor,
            displayName: "CPU die (hottest)",
            source: HIDThermalReader.source,
            sampledAtMonotonic: ContinuousTime.now,
            availability: "available"
        )
    }
}

enum HIDThermalReader {
    static let source = "IOHIDEventSystem/PrimaryUsagePage-0xff00-Usage-5/PMU-tdie"
    static func isValidDieReading(_ value: Double) -> Bool { value.isFinite && value > 0 && value < 125 }
    static func isDieSensor(named name: String) -> Bool {
        name.hasPrefix("PMU") && name.contains("tdie")
    }

    /// Pure selection seam (unit-tested): hottest valid CPU die sensor, if any.
    static func selectHottestDie(in services: [(name: String, value: Double)]) -> (name: String, value: Double)? {
        services.filter { isDieSensor(named: $0.name) && isValidDieReading($0.value) }
            .max(by: { $0.value < $1.value })
    }

    /// Live read. Every failure mode returns nil (caller reports `.unsupported`).
    /// All HID references are balanced inside this scope; nothing is retained.
    static func hottestDieSample() -> (sensor: String, value: Double)? {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY),
              let api = API(handle: handle) else { return nil }
        defer { dlclose(handle) }
        guard let client = api.create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let match = NSMutableDictionary()
        match["PrimaryUsagePage"] = NSNumber(value: 0xff00)
        match["PrimaryUsage"] = NSNumber(value: 5)
        api.setMatching(client, match)
        guard let servicesRef = api.copyServices(client)?.takeRetainedValue() as? NSArray else { return nil }
        var found: [(name: String, value: Double)] = []
        found.reserveCapacity(48)
        for raw in servicesRef {
            let service = Unmanaged<AnyObject>.passUnretained(raw as AnyObject).toOpaque()
            guard let nameRef = api.copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
                  let name = nameRef as? String,
                  let event = api.copyEvent(service, 15, 0, 0)?.takeRetainedValue() else { continue }
            found.append((name: name, value: api.floatValue(event, 0xF0000)))
        }
        guard let best = selectHottestDie(in: found) else { return nil }
        return (sensor: best.name, value: best.value)
    }

    struct API {
        var create: @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        var setMatching: @convention(c) (AnyObject?, CFDictionary?) -> Void
        var copyServices: @convention(c) (AnyObject?) -> Unmanaged<NSArray>?
        var copyProperty: @convention(c) (UnsafeRawPointer?, CFString) -> Unmanaged<AnyObject>?
        var copyEvent: @convention(c) (UnsafeRawPointer?, UInt32, Int64, Int32) -> Unmanaged<AnyObject>?
        var floatValue: @convention(c) (AnyObject?, UInt32) -> Double

        init?(handle: UnsafeMutableRawPointer) {
            func sym<T>(_ name: String) -> T? {
                guard let p = dlsym(handle, name) else { return nil }
                return unsafeBitCast(p, to: T.self)
            }
            guard let create: @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>? =
                    sym("IOHIDEventSystemClientCreate"),
                  let setMatching: @convention(c) (AnyObject?, CFDictionary?) -> Void =
                    sym("IOHIDEventSystemClientSetMatching"),
                  let copyServices: @convention(c) (AnyObject?) -> Unmanaged<NSArray>? =
                    sym("IOHIDEventSystemClientCopyServices"),
                  let copyProperty: @convention(c) (UnsafeRawPointer?, CFString) -> Unmanaged<AnyObject>? =
                    sym("IOHIDServiceClientCopyProperty"),
                  let copyEvent: @convention(c) (UnsafeRawPointer?, UInt32, Int64, Int32) -> Unmanaged<AnyObject>? =
                    sym("IOHIDServiceClientCopyEvent"),
                  let floatValue: @convention(c) (AnyObject?, UInt32) -> Double =
                    sym("IOHIDEventGetFloatValue") else { return nil }
            self.create = create
            self.setMatching = setMatching
            self.copyServices = copyServices
            self.copyProperty = copyProperty
            self.copyEvent = copyEvent
            self.floatValue = floatValue
        }
    }
}
