import Foundation
import Darwin
import CoreGraphics
import IOKit
import IOKit.ps

@_spi(TestInputs)
public struct NativeDisplayFlags {
    public let builtin: Int32
    public let online: Int32
    public let asleep: Int32
    public init(builtin: Int32, online: Int32, asleep: Int32) {
        self.builtin = builtin; self.online = online; self.asleep = asleep
    }
}

/// Read-only OS boundaries. Unknown/malformed data never becomes a safe default.
@_spi(TestInputs)
public struct NativeSafetySystemCalls {
    let batteries: () -> [[String: Any]]?
    let lidProperty: () -> CFTypeRef?
    let displays: () -> [UInt32]?
    let displayFlags: (UInt32) -> NativeDisplayFlags
    let thermal: () -> NativeThermalState

    public init(batteries: @escaping () -> [[String: Any]]?, lidProperty: @escaping () -> CFTypeRef?,
                displays: @escaping () -> [UInt32]?, displayFlags: @escaping (UInt32) -> NativeDisplayFlags,
                thermal: @escaping () -> NativeThermalState) {
        self.batteries = batteries; self.lidProperty = lidProperty; self.displays = displays
        self.displayFlags = displayFlags; self.thermal = thermal
    }

    public static var readOnlySDK: NativeSafetySystemCalls {
        NativeSafetySystemCalls(batteries: {
            guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
            var result: [[String: Any]] = []
            for source in list {
                guard let data = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { return nil }
                result.append(data)
            }
            return result
        }, lidProperty: {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            guard service != 0 else { return nil }
            let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue()
            guard IOObjectRelease(service) == kIOReturnSuccess else { return nil }
            return value
        }, displays: {
            var ids = [CGDirectDisplayID](repeating: 0, count: 32)
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(32, &ids, &count) == .success, count < 32 else { return nil }
            return Array(ids.prefix(Int(count)))
        }, displayFlags: { id in
            NativeDisplayFlags(builtin: Int32(clamping: CGDisplayIsBuiltin(id)), online: Int32(clamping: CGDisplayIsOnline(id)),
                asleep: Int32(clamping: CGDisplayIsAsleep(id)))
        }, thermal: {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return .nominal
            case .fair: return .fair
            case .serious: return .serious
            case .critical: return .critical
            @unknown default: return .unknown
            }
        })
    }

    public func batteryAndAC() -> (Double?, Bool?) {
        guard let values = batteries() else { return (nil, nil) }
        // Only explicitly classified SDK source types may be excluded from uniqueness.
        guard values.allSatisfy({ source in
            guard let type = source["Type"] as? String else { return false }
            return type == "InternalBattery" || type == "UPS"
        }) else { return (nil, nil) }
        let internalSources = values.filter { $0["Type"] as? String == "InternalBattery" }
        guard internalSources.count == 1 else { return (nil, nil) }
        let source = internalSources[0]
        guard let present = source["Is Present"], CFGetTypeID(present as CFTypeRef) == CFBooleanGetTypeID(),
              CFBooleanGetValue(unsafeDowncast(present as CFTypeRef, to: CFBoolean.self)),
              let current = source["Current Capacity"] as? NSNumber,
              let maximum = source["Max Capacity"] as? NSNumber,
              CFGetTypeID(current) != CFBooleanGetTypeID(), CFGetTypeID(maximum) != CFBooleanGetTypeID(),
              current.doubleValue.isFinite, maximum.doubleValue.isFinite,
              current.doubleValue >= 0, maximum.doubleValue > 0,
              current.doubleValue <= maximum.doubleValue else { return (nil, nil) }
        let state = source["Power Source State"] as? String
        let ac: Bool? = state == "AC Power" ? true : (state == "Battery Power" ? false : nil)
        return (current.doubleValue / maximum.doubleValue * 100, ac)
    }

    public func lidState() -> NativeLidState {
        guard let value = lidProperty(), CFGetTypeID(value) == CFBooleanGetTypeID() else { return .unknown }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self)) ? .closed : .open
    }

    public func panelAndTopology() -> (NativePanelState, Int?) {
        guard let first = displays(), first.count < 32,
              Set(first).count == first.count, !first.contains(0) else { return (.unknown, nil) }
        var panels: [NativePanelState] = []
        var external = 0
        for id in first {
            let flags = displayFlags(id)
            guard flags.builtin == 0 || flags.builtin == 1,
                  flags.online == 1 else { return (.unknown, nil) }
            if flags.builtin == 1 {
                panels.append(flags.asleep == 1 ? .asleep : (flags.asleep == 0 ? .awake : .unknown))
            } else { external += 1 }
        }
        guard let second = displays(), first.sorted() == second.sorted() else { return (.unknown, nil) }
        // Valid topology remains known even when internal-panel state is unavailable/ambiguous.
        return (panels.count == 1 ? panels[0] : .unknown, external)
    }
}
