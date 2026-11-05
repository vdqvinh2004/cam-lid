import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

/// Owner gate for spec 017 (User Story 2). These are measurements, not unit tests. Each runs only when its own
/// environment variable names a CSV file, and each starts one CPU-bound process per core for the duration.
@Suite("Sensor timing gate", .serialized)
struct SensorTimingGateTests {
    /// The lid read alone, from a `.utility` and a `.userInitiated` queue, once a second each.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAMLID_SENSOR_GATE_OUT"] != nil))
    func lidReadsUnderFullLoad() async throws {
        let environment = ProcessInfo.processInfo.environment
        let outPath = try #require(environment["CAMLID_SENSOR_GATE_OUT"])
        let seconds = Double(environment["CAMLID_SENSOR_GATE_SECONDS"] ?? "") ?? 180
        let hogs = try startHogs(seconds: seconds)
        defer { for hog in hogs where hog.isRunning { hog.terminate() } }
        try await Task.sleep(for: .seconds(2))   // let the hogs reach full speed before the first read

        let utility = DispatchQueue(label: "gate.utility", qos: .utility)
        let interactive = DispatchQueue(label: "gate.user-initiated", qos: .userInitiated)
        var rows = ["qos,requested_at,queue_wait_s,call_s,total_s,lid_state,availability,reason"]
        let end = ContinuousTime.now + seconds
        while ContinuousTime.now < end {
            rows.append(await lidSample(on: utility, qos: "utility"))
            rows.append(await lidSample(on: interactive, qos: "userInitiated"))
            try await Task.sleep(for: .seconds(1))
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
    }

    /// The production read sequence (`LiveSensorProvider.readHardware`, same order) on the production `.utility`
    /// queue, with each source timed on its own. The worker's stall check covers the whole sum.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAMLID_SENSOR_GATE_SEQUENCE_OUT"] != nil))
    func productionReadSequenceUnderFullLoad() async throws {
        let environment = ProcessInfo.processInfo.environment
        let outPath = try #require(environment["CAMLID_SENSOR_GATE_SEQUENCE_OUT"])
        let seconds = Double(environment["CAMLID_SENSOR_GATE_SECONDS"] ?? "") ?? 180
        let hogs = try startHogs(seconds: seconds)
        defer { for hog in hogs where hog.isRunning { hog.terminate() } }
        try await Task.sleep(for: .seconds(2))

        let worker = DispatchQueue(label: "gate.production", qos: .utility)
        var rows = ["requested_at,battery_s,lid_s,cpu_s,temperature_s,total_s,temperature_availability,temperature_reason"]
        let end = ContinuousTime.now + seconds
        while ContinuousTime.now < end {
            rows.append(await readSequence(on: worker))
            try await Task.sleep(for: .seconds(1))
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
    }

    private func startHogs(seconds: Double) throws -> [Process] {
        var hogs: [Process] = []
        for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
            let hog = Process()
            hog.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            // perl's alarm ends each hog even if this test process dies before it can terminate them.
            hog.arguments = ["-e", "alarm \(Int(seconds) + 60); exec 'yes'"]
            hog.standardOutput = FileHandle.nullDevice
            hog.standardError = FileHandle.nullDevice
            try hog.run()
            hogs.append(hog)
        }
        return hogs
    }

    private func lidSample(on queue: DispatchQueue, qos: String) async -> String {
        await withCheckedContinuation { continuation in
            let requested = ContinuousTime.now
            queue.async {
                let started = ContinuousTime.now
                let observation = LidStateReader.read()
                let finished = ContinuousTime.now
                let fields = [qos,
                    String(format: "%.3f", requested),
                    String(format: "%.6f", started - requested),
                    String(format: "%.6f", finished - started),
                    String(format: "%.6f", finished - requested),
                    "\(observation.state)",
                    observation.availability,
                    observation.reasonCode ?? ""]
                continuation.resume(returning: fields.joined(separator: ","))
            }
        }
    }

    private func readSequence(on queue: DispatchQueue) async -> String {
        await withCheckedContinuation { continuation in
            let requested = ContinuousTime.now
            queue.async {
                let t0 = ContinuousTime.now
                _ = LiveSensorProvider.batteryAndPower()
                let t1 = ContinuousTime.now
                _ = LidStateReader.read()
                let t2 = ContinuousTime.now
                _ = LiveSensorProvider.cpuTicks()
                let t3 = ContinuousTime.now
                let temperature = TemperatureReader.read()
                let t4 = ContinuousTime.now
                let fields = [String(format: "%.3f", requested),
                    String(format: "%.6f", t1 - t0),
                    String(format: "%.6f", t2 - t1),
                    String(format: "%.6f", t3 - t2),
                    String(format: "%.6f", t4 - t3),
                    String(format: "%.6f", t4 - t0),
                    temperature.availability,
                    temperature.reasonCode ?? ""]
                continuation.resume(returning: fields.joined(separator: ","))
            }
        }
    }
}
