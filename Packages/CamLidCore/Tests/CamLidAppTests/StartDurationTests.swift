import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Start duration", .serialized)
struct StartDurationTests {
    @Test @MainActor func startTakesTheDashboardTimerStepsOnly() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suite = "camlid-start-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = AppCoordinator(historyDirectory: root, preferences: defaults,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) })
        coordinator.changeMode(.timed)
        func start(_ duration: String) async throws -> CLIResult {
            await coordinator.startFromControl(try JSONEncoder().encode(CLIOptions(flags: ["mode": "timed", "duration": duration])))
        }
        func session() throws -> [String: Any]? {
            let status = try JSONDecoder().decode(CLIResult.self, from: coordinator.handleControl(.status, payload: Data()))
            return (try JSONSerialization.jsonObject(with: Data(status.json.utf8)) as? [String: Any])?["session"] as? [String: Any]
        }
        // Two minutes is not a timer step, and "0m" is not Infinite: both are refused before any session starts.
        let twoMinutes = try await start("2m")
        #expect(twoMinutes.exitCode == 2 && twoMinutes.json.contains("invalidDuration"))
        let zero = try await start("0m")
        #expect(zero.exitCode == 2)
        #expect(try session() == nil)
        // Infinite is the Dashboard's choice: a timed session with no cap.
        let infinite = try await start("infinite")
        #expect(infinite.exitCode == 0)
        #expect(try session()?["capDeadlineMonotonic"] as? Double == nil)
        coordinator.changeMode(.off)
        coordinator.changeMode(.timed)
        // A listed step caps the session.
        let thirty = try await start("30m")
        #expect(thirty.exitCode == 0)
        #expect(try session()?["capDeadlineMonotonic"] as? Double != nil)
        coordinator.changeMode(.off)
        #expect(await coordinator.flushHistory())
    }

    @Test @MainActor func dashboardSaysWhenAutoIsWaitingAndWarnsWhenClosingTheLidSleepsTheMac() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-dash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suite = "camlid-dash-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = AppCoordinator(historyDirectory: root, preferences: defaults,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) })
        coordinator.changeMode(.auto)
        #expect(coordinator.dashboardData().statusTitle == "Not running")
        await coordinator.startPreviewSession()
        #expect(coordinator.dashboardData().statusTitle == "Waiting for agents")
        // Closed-lid keep-awake is off by default, so a running session says that closing the lid sleeps the Mac.
        #expect(coordinator.dashboardData().bannerMessage?.contains("Closing the lid sleeps this Mac") == true)
        coordinator.changeMode(.off)
        #expect(await coordinator.flushHistory())
    }

    @Test @MainActor func statusReportsTheRunningSessionState() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suite = "camlid-status-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = AppCoordinator(historyDirectory: root, preferences: defaults,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) })
        coordinator.changeMode(.timed)
        func status() throws -> [String: Any] {
            let reply = try JSONDecoder().decode(CLIResult.self, from: coordinator.handleControl(.status, payload: Data()))
            return try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        }
        await coordinator.startPreviewSession()
        // While the session runs, status shows the session's state, the same one start and the Dashboard report.
        #expect(try status()["effectiveState"] as? String == "protected")
        coordinator.changeMode(.off)
        #expect(await coordinator.flushHistory())
    }
}
