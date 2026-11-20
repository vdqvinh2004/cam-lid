import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

/// Answers every request with the same reply, and records which commands the CLI sent to the app.
final class RecordingChannel: IPCChannel, @unchecked Sendable {
    private(set) var sent: [AllowlistedCommand] = []

    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        sent.append(command)
        return try JSONEncoder().encode(CLIResult(json: #"{"accepted":true,"changed":false}"#, exitCode: 0))
    }
}

/// The CLI's routes. Every catalogued command must reach a handler, and every row of the spec 031 audit must name a
/// catalogued command. Together they fail when a command is added to the catalog without a route, or a route goes missing.
@Suite("Agent CLI routes and parity inventory")
struct AgentRoutingTests {
    /// Commands the route test does not run: they install, remove or read the helper and recovery state on this Mac, or pass
    /// a command through. Their routes are still checked by the inventory below.
    private static let notRunHere: Set<String> = ["helper install", "helper uninstall", "helper trust", "helper status", "recover", "run"]

    /// Every row of the audit tables in spec 031, with the catalogued command that serves it.
    private static let inventory: [(function: String, route: String)] = [
        // Menu bar and shortcut
        ("Start an Auto session", "start"),
        ("Stop the session", "stop"),
        ("Global shortcut ⌃⌥⌘K starts or stops Auto", "start"),
        ("Why is my Mac awake?", "diagnose"),
        ("Quit CamLid", "quit"),
        ("Check for Updates…", "update check"),
        ("About CamLid: version and build", "version"),
        ("Open a window", "open"),
        // Dashboard
        ("Start Auto or Timed, with a duration", "start"),
        ("Infinite Timed", "start"),
        ("Click the active mode again to stop", "stop"),
        ("Mode button also saves the mode as the next session mode", "start"),
        ("Click the other mode while a session runs", "start"),
        ("Change the Timed duration of the running session", "session duration"),
        ("Change \"Sleep when done\" of the running Auto session", "session sleep-delay"),
        ("Choose Agents… (opens Settings › Agents)", "open"),
        ("Activity button", "logs list"),
        ("Turn on keep-awake with the lid closed", "config set"),
        ("Install, reinstall or remove the helper", "helper install"),
        ("Update notice (opens Updates)", "update status"),
        ("Metrics, status, reason and banner", "status"),
        ("Agent badges (working and waiting)", "agents list"),
        ("Music badges (playing now)", "music list"),
        // Settings › General
        ("Default Timed duration", "config set"),
        ("Default Sleep when done", "config set"),
        ("Let the display sleep during sessions", "config set"),
        ("Language: System, English, Tiếng Việt", "language set"),
        ("Launch at login", "config set"),
        ("Apply startup preference", "login apply"),
        ("Notification categories", "config set"),
        ("Allow Notifications… (macOS prompt)", "notifications request"),
        ("Check for new releases once a day", "update auto"),
        ("Let AI agents use CamLid (writes the skill file)", "skill install"),
        // Settings › Agents
        ("Per-agent \"may delay sleep\" toggles", "agents enable"),
        ("Enable All, Disable All", "agents enable"),
        ("Music sources: Chromium, Spotify, Apple Music, Safari", "music set"),
        ("Any audio hold (spec 029)", "audio-hold"),
        ("Watched programs: list, add (path or bundle ID), remove", "watch add"),
        ("Watched program: turn on or off", "watch enable"),
        // Settings › Closed Lid
        ("Keep awake with the lid closed", "config set"),
        ("Closed-lid mode", "config set"),
        ("Allow on this untested Mac", "closed-lid acknowledge-untested"),
        ("Allow on battery", "config set"),
        ("Stop below battery level, battery time limit, start on battery at or above", "config set"),
        ("Session time limit", "config set"),
        ("Retain waiting sessions", "config set"),
        ("Stop if CPU stays busy", "config set"),
        ("Changed elsewhere: Use current, Apply my value", "config get"),
        // Activity window
        ("List events; search; filter by type and reason", "logs list"),
        ("Show or hide routine updates", "logs list"),
        ("Export redacted", "logs export"),
        ("Delete one session's history; delete all; the deletion receipt", "logs delete"),
        // Updates window
        ("Read update state: phase, reason, version", "update status"),
        ("Check for updates", "update check"),
        ("Update to a version: download, check, replace, restart", "update install"),
        ("Stop Session and Install", "update install"),
        ("Open Releases", "open"),
        // Sleep diagnostics window
        ("Show what keeps the Mac awake", "diagnose"),
        ("Copy diagnostics", "diagnose"),
        ("Refresh", "diagnose"),
        // Welcome
        ("Detected agents", "agents list"),
        ("Install the helper", "helper install"),
        ("Allow notifications", "notifications request"),
        ("Finish (mark Welcome done)", "welcome complete"),
        // About
        ("Version, build and copyright", "version"),
    ]

    private func reason(_ result: CLIResult) throws -> String? {
        let object = try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
        return object["reason"] as? String
    }

    @Test func everyCataloguedCommandReachesAHandler() throws {
        for spec in CommandCatalog.all where !Self.notRunHere.contains(spec.name) {
            let channel = RecordingChannel()
            let argv = spec.name.split(separator: " ").map(String.init)
            let result = Commands.runWithRealIO(argv: argv, channel: channel)
            #expect(try reason(result) != "unknownCommand", "\(spec.name) has no route")
            // An app command that reached no handler and was not refused for its input fell through to the local default.
            if spec.needsApp, channel.sent.isEmpty {
                #expect(result.exitCode == 2, "\(spec.name) is not sent to the app and was not refused as invalid input")
            }
        }
    }

    @Test func theInventoryCoversEveryAuditRow() {
        #expect(Self.inventory.count == 65)
    }

    @Test func everyAuditRowHasACataloguedRoute() {
        for row in Self.inventory {
            #expect(CommandCatalog.spec(row.route) != nil, "\(row.function) routes to \(row.route), which is not catalogued")
        }
    }
}
