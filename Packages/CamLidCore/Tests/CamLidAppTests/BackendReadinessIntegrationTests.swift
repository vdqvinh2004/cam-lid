import AppKit
import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// Real same-user transport and authoritative Preview coordinator; no backend,
/// GUI launch, assertion, sleep request, or installed-app state is involved.
@Suite("Backend readiness refusal integration", .serialized)
struct BackendReadinessIntegrationTests {
    @Test @MainActor func activePreviewNeverAdmitsLiveOperations() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let suite = "camlid-backend-gate-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let control = root.appendingPathComponent("control")
        let app = AppCoordinator(historyDirectory: root.appendingPathComponent("history"),
            controlDirectory: control, preferences: preferences,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) },
            helperController: HelperController(status: { .notInstalled }, keepAwakeApps: { [] }),
            holdTransportFactory: { NeverTransport() }, closedLidSupportRow: { nil }, systemIdentity: { (nil, nil) })
        app.startControlService()
        defer { app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        let channel = LocalControlChannel(directory: control)

        func cli(_ arguments: [String]) async -> CLIResult {
            await Task.detached {
                Commands.runWithRealIO(argv: arguments, channel: channel)
            }.value
        }
        func object(_ reply: CLIResult) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        }
        func checkUnavailable(_ status: [String: Any]) {
            #expect(status["powerActuation"] as? Bool == false)
            #expect(status["backendVerified"] as? Bool == false)
            #expect(status["leaseVerified"] as? Bool == false)
            #expect(status["effectiveState"] as? String == "unavailable")
            #expect(status["restoration"] as? String == "noPowerResourcesOwned")
            #expect(status["reasonCodes"] as? [String] == ["backendPendingM1"])
        }

        let initial = try object(await cli(["status"]))
        checkUnavailable(initial)
        #expect(initial["activeSessionMode"] is NSNull)

        for mode in [RequestedMode.auto, .timed] {
            app.changeMode(mode)
            await app.startPreviewSession()
            let before = try object(await cli(["status"]))
            checkUnavailable(before)
            #expect(before["activeSessionMode"] as? String == mode.rawValue)
            let session = try #require(before["session"] as? [String: Any])
            let sessionID = try #require(session["id"] as? String)
            let deadline = session["capDeadlineMonotonic"] as? Double

            for command in [AllowlistedCommand.start] {
                let reply = try await Task.detached {
                    try JSONDecoder().decode(CLIResult.self,
                        from: channel.send(command: command, payload: Data()))
                }.value
                #expect(reply.exitCode == 3)
                let denied = try object(reply)
                #expect(denied["accepted"] as? Bool == false)
                #expect(denied["reason"] as? String == "sessionAlreadyActive")
            }
            let start = await cli(["start", "--mode", mode.rawValue])
            #expect(start.exitCode == 3)
            #expect(try object(start)["reason"] as? String == "sessionAlreadyActive")

            let marker = root.appendingPathComponent("must-not-launch-" + mode.rawValue)
            let protectedRun = await cli(["run", "--keep-awake", "--", "/usr/bin/touch", marker.path])
            #expect(protectedRun.exitCode == 3)
            #expect(try object(protectedRun)["reason"] as? String == "externalObservationOnly")
            #expect(!FileManager.default.fileExists(atPath: marker.path))

            for arguments in [["sleep", "--dry-run"], ["sleep"]] {
                let reply = await cli(arguments)
                #expect(reply.exitCode == 3)
                let decision = try JSONDecoder().decode(GuardedSleepDecision.self, from: Data(reply.json.utf8))
                #expect(!decision.eligible)
                #expect(decision.outcome == "blocked")
                #expect(decision.blockers.contains("previewOnly"))
            }
            let after = try object(await cli(["status"]))
            checkUnavailable(after)
            let remaining = try #require(after["session"] as? [String: Any])
            #expect(remaining["id"] as? String == sessionID)
            #expect(remaining["capDeadlineMonotonic"] as? Double == deadline)
            #expect(after["revision"] as? Int == before["revision"] as? Int)

            let stop = await cli(["stop"])
            #expect(stop.exitCode == 0)
            #expect(try object(stop)["cleanupOutcome"] as? String == "noPowerResourcesOwned")
            let stopped = try object(await cli(["status"]))
            checkUnavailable(stopped)
            #expect(stopped["activeSessionMode"] is NSNull)
            #expect(stopped["session"] == nil)
        }
        #expect(await app.flushHistory())
    }
}
