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
        let preferences = MemoryPreferences()
        defer { try? FileManager.default.removeItem(at: root) }
        let control = root.appendingPathComponent("control")
        let app = AppCoordinator(locations: .test(root: root, control: control), preferences: preferences,
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
            let readiness = status["protection"] as? [String: Any]
            // The top-level effectiveState is the session's while one runs; readiness itself is what is unavailable here.
            #expect(readiness?["readinessState"] as? String == "Needs setup")
            #expect(status["restoration"] as? String == "noPowerResourcesOwned")
            #expect(status["reasonCodes"] as? [String] == readiness?["blockerCodes"] as? [String])
        }

        // The control socket answers once its listener is up and the main actor is free; a first read that races either is retried.
        var initialReply = await cli(["status"])
        for _ in 0..<20 where initialReply.json.contains("\"accepted\":false") {
            try await Task.sleep(nanoseconds: 50_000_000)
            initialReply = await cli(["status"])
        }
        let initial = try object(initialReply)
        checkUnavailable(initial)
        #expect(initial["activeSessionMode"] is NSNull)

        for mode in [RequestedMode.auto, .timed] {
            // Each mode starts its own session: the previous one must end, or its mode would carry over.
            _ = await cli(["stop"])
            app.changeMode(mode)
            await app.startPreviewSession()
            let before = try object(await cli(["status"]))
            checkUnavailable(before)
            #expect(before["activeSessionMode"] as? String == mode.rawValue)
            let session = try #require(before["session"] as? [String: Any])
            let sessionID = try #require(session["id"] as? String)
            let deadline = session["capDeadlineMonotonic"] as? Double

            // A start with no flags asks for Auto. The Auto session that runs changes nothing, so that start is an accepted
            // no-op, and no power is claimed. A Timed session is a different session, so asking for Auto is refused.
            let rawStart = try await Task.detached {
                try JSONDecoder().decode(CLIResult.self, from: channel.send(command: .start, payload: Data()))
            }.value
            let rawObject = try object(rawStart)
            if mode == .auto {
                #expect(rawStart.exitCode == 0)
                #expect(rawObject["outcome"] as? String == "alreadyRunning")
                #expect(rawObject["changed"] as? Bool == false)
                #expect(rawObject["powerActuation"] as? Bool == false)
            } else {
                #expect(rawStart.exitCode == 3)
                #expect(rawObject["accepted"] as? Bool == false)
                #expect(rawObject["reason"] as? String == "sessionAlreadyActive")
            }
            // A Timed session runs its own duration, so a different one is refused until --replace names the switch.
            let start = mode == .auto
                ? await cli(["start", "--mode", "auto"])
                : await cli(["start", "--mode", "timed", "--duration", "45m"])
            #expect(start.exitCode == (mode == .auto ? 0 : 3))
            if mode != .auto {
                #expect(try object(start)["reason"] as? String == "sessionAlreadyActive")
            }

            let marker = root.appendingPathComponent("must-not-launch-" + mode.rawValue)
            // Only an Auto session admits a command, and only with a verified backend. The lid-open assertion is
            // verified in this fixture, so Auto runs the command; the other modes refuse it and launch nothing.
            let protectedRun = await cli(["run", "--", "/usr/bin/touch", marker.path])
            if mode == .auto {
                #expect(protectedRun.exitCode == 0)
                #expect(FileManager.default.fileExists(atPath: marker.path))
            } else {
                #expect(protectedRun.exitCode == 3)
                #expect(try object(protectedRun)["reason"] as? String == "commandAdmissionDenied")
                #expect(!FileManager.default.fileExists(atPath: marker.path))
            }

            for arguments in [["sleep", "--dry-run"], ["sleep"]] {
                let reply = await cli(arguments)
                #expect(reply.exitCode == 3)
                let decision = try JSONDecoder().decode(GuardedSleepDecision.self, from: Data(reply.json.utf8))
                #expect(!decision.eligible)
                #expect(decision.outcome == "blocked")
                #expect(decision.blockers.contains("backendUnverified"))
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
