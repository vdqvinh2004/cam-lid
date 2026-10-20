import Foundation
import CoreGraphics
import IOKit.ps
import CamLidCore
import Dispatch

struct SleepDisplayObservation: Sendable, Equatable {
    let state: DisplayState
    let sampledAtMonotonic: Double
}

struct RecentInputObservation: Sendable, Equatable {
    let idleSeconds: Double?
    let sampledAtMonotonic: Double
}

/// Read-only battery, thermal pressure, display and physical lid observations.
/// Hardware reads run on one utility worker. A blocked source can delay refresh,
/// but never blocks the app's main thread or creates a queue of stale work.
public final class LiveSensorProvider: SensorProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let workerQueue = DispatchQueue(label: "dev.camlid.sensor-read", qos: .utility)
    private let sampleInterval: Double
    private let clock: @Sendable () -> Double
    private let thermalReader: @Sendable () -> ThermalPressure
    private let injectedReader: (@Sendable (Double) -> SensorReadings)?

    // Protected by `lock`; the reader itself runs only on `workerQueue`.
    private var sampler = CPUTickSampler()
    private var latestReadings: SensorReadings?
    private var lastSampleStartedAt: Double?
    private var workerInFlight = false

    public convenience init() {
        self.init(
            sampleInterval: 1,
            clock: { ContinuousTime.now },
            thermalReader: { ThermalMapper.map(ProcessInfo.processInfo.thermalState) },
            reader: nil
        )
    }

    /// Internal injection point keeps slow-reader and ordering behavior testable
    /// without changing the public, read-only production API.
    init(
        sampleInterval: Double,
        clock: @escaping @Sendable () -> Double,
        thermalReader: @escaping @Sendable () -> ThermalPressure,
        reader: (@Sendable (Double) -> SensorReadings)?
    ) {
        self.sampleInterval = sampleInterval.isFinite && sampleInterval > 0 ? sampleInterval : 1
        self.clock = clock
        self.thermalReader = thermalReader
        injectedReader = reader
    }

    public func read() -> SensorReadings {
        let now = clock()
        // ProcessInfo thermal state is a cheap, public, in-process value. Read it
        // every time so a critical transition bypasses a slow/hung IOKit worker.
        let thermal = thermalReader()

        lock.lock()
        if !workerInFlight, shouldStartSample(at: now) {
            workerInFlight = true
            lastSampleStartedAt = now
            workerQueue.async { [weak self] in
                guard let self else { return }
                let readings: SensorReadings
                if let injectedReader = self.injectedReader {
                    readings = injectedReader(now)
                } else {
                    readings = self.readHardware(startedAt: now)
                }
                self.finish(readings, startedAt: now, finishedAt: self.clock())
            }
        }
        let cached = latestReadings
        lock.unlock()

        let lid = cached?.lidObservation?.projected(now: now)
            ?? LidObservation(availability: "error", reasonCode: "samplePending")
        let criticalTime = thermal == .critical && now.isFinite && now >= 0 ? now : nil
        return SensorReadings(
            batteryPercent: cached?.batteryPercent,
            powerSource: cached?.powerSource ?? .unknown,
            thermalPressure: thermal,
            cpuPercent: cached?.cpuPercent,
            lidState: lid.state,
            internalDisplayState: cached?.internalDisplayState ?? .unknown,
            measuredAtMonotonic: cached?.measuredAtMonotonic ?? 0,
            lidObservation: lid,
            temperature: cached?.temperature ?? .unsupported,
            criticalThermalSampledAtMonotonic: criticalTime
        )
    }

    private func shouldStartSample(at now: Double) -> Bool {
        guard now.isFinite, now >= 0 else { return false }
        guard let lastSampleStartedAt else { return true }
        return now >= lastSampleStartedAt && now - lastSampleStartedAt >= sampleInterval
    }

    private func finish(_ readings: SensorReadings, startedAt: Double, finishedAt: Double) {
        let elapsed = finishedAt - startedAt
        let lid: LidObservation
        if !elapsed.isFinite || elapsed < 0 || elapsed > 0.2 {
            // The source may have returned a plausible state after a long stall.
            // Timestamping it as current would make stale physical state look safe.
            lid = LidObservation(availability: "error", reasonCode: "slowSensorRead")
        } else if let source = readings.lidObservation {
            lid = LidObservation(
                state: source.state,
                sampledAtMonotonic: startedAt,
                availability: source.availability,
                reasonCode: source.reasonCode
            )
        } else {
            lid = LidObservation(availability: "error", reasonCode: "missingSensorRead")
        }
        // Numerical die readings share the lid stall budget: a slow worker must not
        // present aged silicon data as current.
        let temperature: TemperatureObservation
        if !elapsed.isFinite || elapsed < 0 || elapsed > 0.2 {
            temperature = TemperatureObservation(availability: "error", reasonCode: "slowSensorRead")
        } else {
            temperature = readings.temperature
        }

        let completed = SensorReadings(
            batteryPercent: readings.batteryPercent,
            powerSource: readings.powerSource,
            // Thermal data comes from `read()` directly, never from this cache.
            thermalPressure: .unknown,
            cpuPercent: readings.cpuPercent,
            lidState: lid.state,
            internalDisplayState: readings.internalDisplayState,
            measuredAtMonotonic: startedAt,
            lidObservation: lid,
            temperature: temperature
        )
        lock.lock()
        latestReadings = completed
        workerInFlight = false
        lock.unlock()
    }

    private func readHardware(startedAt: Double) -> SensorReadings {
        let (battery, power) = Self.batteryAndPower()
        let lid = LidStateReader.read()
        // This function is called only by the serial worker. `sampler` therefore
        // has a single writer and the main thread never waits for Mach/IOKit.
        let cpu = sampler.sample(Self.cpuTicks())
        // Numerical die read shares the worker: ~64ms typical, bounded by the
        // 200ms stall guard in `finish`. Any failure reports `.unsupported`.
        let temperature = TemperatureReader.read()
        return SensorReadings(
            batteryPercent: battery,
            powerSource: power,
            thermalPressure: .unknown,
            cpuPercent: cpu,
            lidState: lid.state,
            internalDisplayState: Self.internalDisplayState(),
            measuredAtMonotonic: startedAt,
            lidObservation: lid,
            temperature: temperature
        )
    }

    static func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
    }

    static func allDisplaysState() -> DisplayState {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &displays, &count) == .success, count > 0, count < 32 else { return .unknown }
        return displayState(displays.prefix(Int(count)).map { CGDisplayIsAsleep($0) != 0 })
    }
    static func displayObservation() -> SleepDisplayObservation {
        let sampledAt = ContinuousTime.now
        return SleepDisplayObservation(state: allDisplaysState(), sampledAtMonotonic: sampledAt)
    }
    static func inputIdleSeconds() -> Double? {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return nil }
        let value = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return value.isFinite && value >= 0 ? value : nil
    }
    static func recentInputObservation() -> RecentInputObservation {
        let sampledAt = ContinuousTime.now
        return RecentInputObservation(idleSeconds: inputIdleSeconds(), sampledAtMonotonic: sampledAt)
    }
    static func internalDisplayState() -> DisplayState {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return .unknown }
        let builtins = displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
        // No built-in display reported is unknown, never evidence of sleep.
        return displayState(builtins.map { CGDisplayIsAsleep($0) != 0 })
    }

    static func displayState(_ builtinSleepStates: [Bool]) -> DisplayState {
        guard !builtinSleepStates.isEmpty else { return .unknown }
        return builtinSleepStates.allSatisfy { $0 } ? .asleep : .awake
    }

    static func batteryAndPower() -> (Double?, PowerSource) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
            let source = list.first,
            let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any]
        else { return (nil, .unknown) }
        let current = info[kIOPSCurrentCapacityKey as String] as? Double
        let capacity = info[kIOPSMaxCapacityKey as String] as? Double
        let battery: Double? =
            if let current, let capacity, capacity > 0 {
                min(100, max(0, current / capacity * 100))
            } else { nil }
        let state = info[kIOPSPowerSourceStateKey as String] as? String
        let power: PowerSource =
            state == (kIOPSACPowerValue as String) ? .ac
            : state == (kIOPSBatteryPowerValue as String) ? .battery : .unknown
        return (battery, power)
    }
}

/// Pure qualitative-thermal mapping (unit-testable without hardware).
public enum ThermalMapper: Sendable {
    public static func map(_ state: ProcessInfo.ThermalState) -> ThermalPressure {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}

/// Aggregate tick deltas across all CPUs give a normalized 0...100 percentage.
/// First read, counter reset, failed read, and unchanged ticks remain unknown.
struct CPUTickSampler {
    private var previous: [UInt32]?

    mutating func sample(_ ticks: [UInt32]?) -> Double? {
        guard let ticks, ticks.count == 4 else { previous = nil; return nil }
        defer { previous = ticks }
        guard let previous, zip(ticks, previous).allSatisfy({ $0 >= $1 }) else { return nil }
        let deltas = zip(ticks, previous).map { UInt64($0 - $1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total) * 100
    }
}
