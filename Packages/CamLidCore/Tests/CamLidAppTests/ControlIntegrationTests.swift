import AppKit
import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Preview coordinator integration", .serialized)
struct ControlIntegrationTests {
    @Test @MainActor func legacyIngressRefusesThroughActualTransportAndCLI() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let suite = "camlid-outside-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let control = root.appendingPathComponent("control")
        let coordinator = AppCoordinator(historyDirectory: root.appendingPathComponent("history"), controlDirectory: control, preferences: defaults)
        coordinator.startControlService()
        defer { coordinator.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let channel = LocalControlChannel(directory: control)
        for command in [AllowlistedCommand.event, .agentDiagnostic, .run, .admitCommand, .renewCommand, .finishCommand] {
            // The wire preserves the denial class, deliberately not its internal detail.
            await #expect(throws: IPCError.policyDenied("controlDenied")) {
                try await Task.detached { try channel.send(command: command, payload: Data("PRIVATE".utf8)) }.value
            }
        }
        let marker = root.appendingPathComponent("must-not-launch")
        if let executable = ProcessInfo.processInfo.environment["CAMLID_CLI_PATH"] {
            for arguments in [["bridge", "--provider", "codex", "--stdin"], ["event", "--stdin"],
                              ["run", "--", "/usr/bin/touch", marker.path]] {
                let binary = await Task.detached { () -> (Int32, String) in
                    let process = Process(); let output = Pipe()
                    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
                    process.environment = ProcessInfo.processInfo.environment.merging(["CAMLID_CONTROL_DIRECTORY": control.path]) { _, new in new }
                    process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
                    do { try process.run(); process.waitUntilExit() }
                    catch { return (127, "launch failed") }
                    return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
                }.value
                #expect(binary.0 == 3 && binary.1.contains("externalObservationOnly") && !binary.1.contains("PRIVATE"))
            }
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        let status = try JSONDecoder().decode(CLIResult.self, from: coordinator.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(status.json.utf8)) as? [String: Any])
        #expect((object["tasks"] as? [[String: Any]])?.isEmpty == true)
        #expect(object["powerActuation"] as? Bool == false)
        #expect(await coordinator.flushHistory())
    }

    @Test @MainActor func modeChangesKeepCapAndOffEndsPreview() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-mode-\(UUID().uuidString)")
        let suite = "camlid-mode-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let coordinator = AppCoordinator(historyDirectory: root, preferences: defaults,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) })
        coordinator.changeMode(.timed)
        await coordinator.startPreviewSession()
        func status() throws -> [String: Any] {
            let result = try JSONDecoder().decode(CLIResult.self, from: coordinator.handleControl(.status, payload: Data()))
            return try JSONSerialization.jsonObject(with: Data(result.json.utf8)) as! [String: Any]
        }
        let first = try #require(try status()["session"] as? [String: Any])
        coordinator.changeMode(.auto)
        let changed = try #require(try status()["session"] as? [String: Any])
        #expect(first["capDeadlineMonotonic"] as? Double == changed["capDeadlineMonotonic"] as? Double)
        coordinator.changeMode(.off)
        #expect(try status()["session"] == nil)
        #expect(await coordinator.flushHistory())
        let stored = FileHistoryStorage(directory: root).load()
        #expect(stored.contains { $0.reasonCodes.contains("modeOff") && $0.sessionID != nil })
    }

    @Test @MainActor func actualTransportUsesPersistedConfigAndHistory() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "camlid-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let control = root.appendingPathComponent("control")
        let coordinator = AppCoordinator(historyDirectory: root.appendingPathComponent("history"), controlDirectory: control, preferences: defaults)
        coordinator.startControlService()
        defer { coordinator.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let channel = LocalControlChannel(directory: control)
        let patch = root.appendingPathComponent("patch.json")
        try Data("{\"runCapMinutes\":30}".utf8).write(to: patch)
        let dry = await Task.detached { Commands.runWithRealIO(argv: ["config", "set", "--file", patch.path, "--dry-run"], channel: channel) }.value
        #expect(dry.exitCode == 0)
        let apply = await Task.detached { Commands.runWithRealIO(argv: ["config", "set", "--file", patch.path], channel: channel) }.value
        #expect(apply.exitCode == 0)
        let restored = AppCoordinator(historyDirectory: root.appendingPathComponent("history"), controlDirectory: root.appendingPathComponent("unused"), preferences: defaults)
        let restoredResult = try JSONDecoder().decode(CLIResult.self, from: restored.handleControl(.configGet, payload: Data()))
        #expect(restoredResult.json.contains("\"runCapMinutes\":30"))
        let get = await Task.detached { Commands.runWithRealIO(argv: ["config", "get"], channel: channel) }.value
        #expect(get.exitCode == 0 && get.json.contains("\"runCapMinutes\":30"))
        let status = await Task.detached { Commands.runWithRealIO(argv: ["status"], channel: channel) }.value
        #expect(status.exitCode == 0 && status.json.contains("\"powerActuation\":false"))
        #expect(status.json.contains("\"updates\"") && status.json.contains("manualCheckReady"))
        #expect(status.json.contains("\"installationAvailable\":false"))
        if let executable = ProcessInfo.processInfo.environment["CAMLID_CLI_PATH"] {
            let binary = await Task.detached { () -> (Int32, String) in
                let process = Process(); let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable); process.arguments = ["status", "--json"]
                process.environment = ProcessInfo.processInfo.environment.merging(["CAMLID_CONTROL_DIRECTORY": control.path]) { _, new in new }
                process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit() } catch { return (127, "launch failed") }
                return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            }.value
            #expect(binary.0 == 0 && binary.1.contains("\"powerActuation\":false"))
        }
        let start = await Task.detached { Commands.runWithRealIO(argv: ["start", "--mode", "manual"], channel: channel) }.value
        #expect(start.exitCode == 3)
        let history = root.appendingPathComponent("export.json")
        let export = await Task.detached { Commands.runWithRealIO(argv: ["logs", "export", "--output", history.path], channel: channel) }.value
        #expect(export.exitCode == 0)
        let rows = try JSONDecoder().decode([RedactedTransition].self, from: Data(contentsOf: history))
        #expect(rows.contains { $0.reasonCodes.contains("configApplied") })
        let wrapper = await Task.detached { Commands.runWithRealIO(argv: ["run", "--", "/usr/bin/true"], channel: channel) }.value
        #expect(wrapper.exitCode == 3 && wrapper.json.contains("externalObservationOnly"))
        let agents = await Task.detached { Commands.runWithRealIO(argv: ["agents", "list"], channel: channel) }.value
        #expect(!agents.json.contains("completed"))
        #expect(await coordinator.flushHistory())
        let storage = FileHistoryStorage(directory: root.appendingPathComponent("history"))
        #expect(storage.load().count >= rows.count)
    }
}
