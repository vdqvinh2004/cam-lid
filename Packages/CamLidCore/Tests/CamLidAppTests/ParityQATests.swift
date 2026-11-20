import AppKit
import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// T073: the audit rows that were ✗ or ◐, each run once through the app's own function and once through `camlid`, from the
/// same starting state. The app side is the function the window calls. The CLI side runs `camlid` over the control channel.
/// Both sides run on QA copies (the test fixtures), so the owner's data, network, login items and notifications are not used.
/// Windows, the network, and the installer cannot be checked headlessly; spec 031's QA record lists those rows.
@MainActor
@Suite("QA parity: the app and the CLI from the same start", .serialized)
struct ParityQATests {
    private enum ParityError: Error { case notSaved }

    /// One row: the state both sides start from, the app's action, the CLI's arguments, what each side reports, and whether
    /// the CLI is expected to refuse on a QA copy.
    private struct Row {
        let function: String
        let setup: (AppCoordinator) async throws -> Void
        let app: (AppCoordinator) async throws -> Void
        let cli: [String]
        let observe: (AppCoordinator) throws -> [String: String]
        var refused = false
    }

    private struct Outcome {
        let baseline: [String: String]
        let observed: [String: String]
        let cli: CLIResult?
    }

    private static func save(_ app: AppCoordinator, _ values: [String: Any]) async throws {
        let patch = try ConfigPatch(jsonDictionary: values)
        guard case .saved = await app.applySettingsPatchAsync(patch, expectedRevision: app.revision) else {
            throw ParityError.notSaved
        }
    }

    private static func status(_ app: AppCoordinator) throws -> [String: Any] {
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        return try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
    }

    /// The running session's mode, or "none".
    private static func mode(_ app: AppCoordinator) throws -> String {
        try (status(app)["session"] as? [String: Any])?["requestedMode"] as? String ?? "none"
    }

    /// The running session's timer in whole seconds, "infinite" when it has no cap, or "none" when no session runs.
    private static func timer(_ app: AppCoordinator) throws -> String {
        guard let session = try status(app)["session"] as? [String: Any] else { return "none" }
        guard let cap = session["capDeadlineMonotonic"] as? Double, let start = session["startedAtMonotonic"] as? Double else {
            return "infinite"
        }
        return "\(Int((cap - start).rounded()))s"
    }

    private static func enrolled(_ app: AppCoordinator) -> String {
        app.config.adapterEnrollment.sorted().joined(separator: ",")
    }

    private var rows: [Row] {
        let provider = AgentBadgeState.providers.first ?? "codex"
        return [
            Row(function: "Change the Timed duration of the running session",
                setup: { app in
                    try await ParityQATests.save(app, ["mode": "timed", "timerMinutes": 60])
                    await app.startPreviewSession()
                },
                app: { app in _ = app.changeTimerDuration(45, expectedRevision: app.revision) },
                cli: ["session", "duration", "45m"],
                observe: { app in ["timer": try ParityQATests.timer(app), "mode": try ParityQATests.mode(app)] }),
            Row(function: "Language: System, English, Tiếng Việt",
                setup: { _ in },
                app: { app in app.setLanguage(.english) },
                cli: ["language", "set", "english"],
                observe: { app in ["language": app.language.rawValue] }),
            Row(function: "Music sources: Chromium",
                setup: { _ in },
                app: { app in app.setMusicSource(.browser, true) },
                cli: ["music", "set", "chromium", "on"],
                observe: { app in ["chromium": "\(app.preferences.bool(forKey: AppCoordinator.musicKey(.browser)))"] }),
            Row(function: "Any audio hold",
                setup: { _ in },
                app: { app in app.setAnyAudioHold(true) },
                cli: ["audio-hold", "on"],
                observe: { app in ["hold": "\(app.preferences.bool(forKey: AppCoordinator.anyAudioKey))"] }),
            Row(function: "Per-agent \"may delay sleep\" toggles",
                setup: { app in try await ParityQATests.save(app, ["adapterEnrollment": [String]()]) },
                app: { app in try await ParityQATests.save(app, ["adapterEnrollment": [provider]]) },
                cli: ["agents", "enable", provider],
                observe: { app in ["enrolled": ParityQATests.enrolled(app)] }),
            Row(function: "Enable All, Disable All",
                setup: { app in try await ParityQATests.save(app, ["adapterEnrollment": [String]()]) },
                app: { app in try await ParityQATests.save(app, ["adapterEnrollment": AgentBadgeState.providers]) },
                cli: ["agents", "enable", "--all"],
                observe: { app in ["enrolled": ParityQATests.enrolled(app)] }),
            Row(function: "Allow on this untested Mac",
                setup: { _ in },
                app: { app in app.setUntestedAcknowledgement(true) },
                cli: ["closed-lid", "acknowledge-untested", "--confirm"],
                observe: { app in ["acknowledged": "\(app.untestedAcknowledgementStored)"] }),
            Row(function: "Check for new releases once a day",
                setup: { app in app.updates.setAutomaticChecks(false) },
                app: { app in app.updates.setAutomaticChecks(true) },
                cli: ["update", "auto", "on"],
                observe: { app in ["automatic": "\(app.updates.automaticChecks)"] }),
            Row(function: "Finish (mark Welcome done)",
                setup: { _ in },
                app: { app in _ = app.finishOnboarding() },
                cli: ["welcome", "complete"],
                observe: { app in ["onboarded": "\(app.preferences.bool(forKey: AppCoordinator.onboardedKey))"] }),
            Row(function: "Mode button also saves the mode as the next session mode",
                setup: { app in try await ParityQATests.save(app, ["timerMinutes": 45]) },
                app: { app in _ = await app.activateDashboardMode(.timed, expectedRevision: app.revision) },
                cli: ["start", "--mode", "timed", "--duration", "45m", "--save-mode"],
                observe: { app in [
                    "savedMode": app.config.mode.rawValue,
                    "session": try ParityQATests.mode(app),
                    "timer": try ParityQATests.timer(app),
                ] }),
            Row(function: "Click the other mode while a session runs",
                setup: { app in
                    try await ParityQATests.save(app, ["mode": "auto", "timerMinutes": 45])
                    await app.startPreviewSession()
                },
                app: { app in _ = await app.activateDashboardMode(.timed, expectedRevision: app.revision) },
                cli: ["start", "--mode", "timed", "--duration", "45m", "--replace"],
                observe: { app in ["session": try ParityQATests.mode(app), "timer": try ParityQATests.timer(app)] }),
            Row(function: "Allow Notifications… (macOS prompt)",
                setup: { _ in },
                app: { app in await app.outcomeNotifications.authorizeFromUserAction() },
                cli: ["notifications", "request"],
                observe: { app in ["permission": app.outcomeNotifications.permissionState] },
                refused: true),
        ]
    }

    /// Runs one side of a row in its own QA-copy fixture, from the row's starting state.
    private func run(_ row: Row, onApp: Bool) async throws -> Outcome {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let app = fixture.makeCoordinator(systemIdentity: { (model: "Mac16,1", osBuild: "25A100") })
        app.startControlService()
        defer { app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification)) }
        try await row.setup(app)
        let baseline = try row.observe(app)
        var cli: CLIResult?
        if onApp {
            try await row.app(app)
        } else {
            let channel = LocalControlChannel(directory: fixture.root.appendingPathComponent("control"))
            let argv = row.cli
            cli = await Task.detached { Commands.runWithRealIO(argv: argv, channel: channel) }.value
        }
        return Outcome(baseline: baseline, observed: try row.observe(app), cli: cli)
    }

    @Test func theAppAndTheCLIReachTheSameStateFromTheSameStart() async throws {
        for row in rows {
            let onApp = try await run(row, onApp: true)
            let onCLI = try await run(row, onApp: false)
            #expect(onCLI.observed == onApp.observed,
                "\(row.function): the app left \(onApp.observed), the CLI left \(onCLI.observed)")
            if row.refused {
                #expect((onCLI.cli?.exitCode ?? 0) != 0, "\(row.function): the CLI should refuse on a QA copy")
            } else {
                #expect(onCLI.cli?.exitCode == 0, "\(row.function): the CLI refused")
                #expect(onApp.observed != onApp.baseline, "\(row.function): the app changed nothing")
                #expect(onCLI.observed != onCLI.baseline, "\(row.function): the CLI changed nothing")
            }
        }
    }
}
