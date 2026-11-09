import AppKit
import CamLidCore

/// Reports the Standard-mode helper's real install state and runs the fixed install/remove commands behind
/// the macOS administrator prompt. The privileged work is the app's own executable run with `--helper-admin`
/// (see `HelperAdminCommand`); no caller-supplied command or path reaches the shell.
@MainActor public final class HelperController {
    public private(set) var state = "unknown"
    public private(set) var message = "Helper status has not been checked."
    public private(set) var busy = false
    /// Other keep-awake apps currently running or loaded (spec 014 FR-019).
    public private(set) var keepAwakeApps: [KeepAwakeApp] = []
    private let readStatus: @Sendable () -> HelperInstallStatus
    private let readKeepAwakeApps: @Sendable () -> [KeepAwakeApp]
    private let runAdmin: @Sendable (String) -> HelperOperationResult
    private var onChange: () -> Void = {}

    public init(status: (@Sendable () -> HelperInstallStatus)? = nil,
                runAdmin: (@Sendable (String) -> HelperOperationResult)? = nil,
                keepAwakeApps: (@Sendable () -> [KeepAwakeApp])? = nil) {
        readStatus = status ?? { HelperInstaller().status(appBundle: Bundle.main.bundleURL) }
        readKeepAwakeApps = keepAwakeApps ?? { HelperController.detectKeepAwakeApps() }
        self.runAdmin = runAdmin ?? { HelperController.runWithAdministratorPrompt(operation: $0) }
    }

    public func observe(_ change: @escaping () -> Void) { onChange = change }

    public func refresh() {
        guard !busy else { return }
        let read = readStatus
        let readKeepAwakeApps = readKeepAwakeApps
        Task { [weak self] in
            let status = await Task.detached { read() }.value
            let apps = await Task.detached { readKeepAwakeApps() }.value
            await MainActor.run {
                self?.keepAwakeApps = apps
                self?.apply(status)
            }
        }
    }

    public func install() { perform("install") }
    public func uninstall() { perform("uninstall") }

    private func perform(_ operation: String) {
        guard !busy else { return }
        busy = true
        message = operation == "install" ? "Waiting for administrator approval…" : "Removing the helper…"
        onChange()
        let run = runAdmin
        let read = readStatus
        Task { [weak self] in
            let result = await Task.detached { run(operation) }.value
            let status = await Task.detached { read() }.value
            await MainActor.run {
                guard let self else { return }
                self.busy = false
                self.apply(status)
                if !result.accepted { self.message = HelperController.describe(result) }
                self.onChange()
            }
        }
    }

    private func apply(_ status: HelperInstallStatus) {
        switch status {
        case .notInstalled: state = "notInstalled"; message = "The closed-lid helper is not installed."
        case .installed(let loaded):
            state = loaded ? "installed" : "installedNotLoaded"
            message = loaded ? "Installed and running." : "Installed but not running. Reinstall or restart the Mac."
        case .needsReauthorization:
            state = "needsReauthorization"; message = "This build of CamLid changed since the helper was installed. Reinstall to authorize it."
        case .needsHelperUpdate:
            state = "needsHelperUpdate"; message = "This version of CamLid ships a newer helper. Reinstall to update it."
        case .helperIdentityMismatch:
            state = "helperIdentityMismatch"; message = "The installed helper does not match its pin. Remove it and install again."
        case .partial(let missing) where Set(missing) == ["helper", "daemonPlist", "recoveryPlist"]:
            // Only an identity file from an earlier install is present; Install keeps it as a backup.
            state = "notInstalled"; message = "The closed-lid helper is not installed."
        case .partial: state = "partial"; message = "The helper installation is incomplete. Remove it and install again."
        }
        onChange()
    }

    nonisolated static func pids(named name: String) -> [Int32] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", name]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }
    }

    /// True when an agent process (Claude Code, Codex, OpenCode, …) is among the first four ancestors.
    nonisolated static func startedByAgent(_ pid: Int32,
                                            entry: (Int32) -> (parent: Int32, name: String)? = {
                                                NativeProcessList.kernelEntry($0).map { ($0.parent, $0.name) } }) -> Bool {
        var current = entry(pid)?.parent ?? 0
        for _ in 0..<4 where current > 1 {
            guard let found = entry(current) else { return false }
            if NativeProcessList.executableNames.contains(NativeProcessList.agentName(pid: current, processName: found.name)) { return true }
            current = found.parent
        }
        return false
    }

    nonisolated static func detectKeepAwakeApps() -> [KeepAwakeApp] {
        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Claude Code runs `caffeinate` while it works: that is an agent CamLid already observes, not another
        // keep-awake app, and the notice would show during every agent turn.
        let processes = Set(KeepAwakeApps.processNames.keys.filter { name in
            pids(named: name).contains { !startedByAgent($0) }
        })
        let installer = HelperInstaller()
        return KeepAwakeApps.detect(runningBundleIDs: bundleIDs, runningProcesses: processes, isRunning: installer.isServiceRunning)
    }

    nonisolated static func describe(_ result: HelperOperationResult) -> String {
        switch result.reason {
        case "administratorRequired": return "Administrator approval is required."
        case "cancelled": return "Cancelled."
        case "helperSourceMissing": return "This build of CamLid does not include the helper."
        case "signatureUnreadable": return "CamLid and its helper must be signed before the helper can be installed."
        case "labelInUse": return "Another helper with CamLid's name is already running (an earlier build). In Terminal run: sudo launchctl bootout system/com.camlid.power-helper, then install again."
        case "previousPinsBackupExists": return "A backup of an earlier identity file already exists in /Library/Application Support/CamLidPowerHelper. Remove the helper first."
        case "bootstrapFailed": return "macOS refused to start the helper. Nothing was left installed; try again or restart the Mac."
        case "foreignPinsPresent": return "An earlier CamLid identity file exists. In Terminal run: sudo camlid helper install --replace-pins"
        case "alreadyInstalledDifferently": return "A different helper is already installed. Remove it first."
        case "helperSignerMismatch": return "The helper is not signed by the same certificate as CamLid, so it was not installed."
        case "restoreUnresolved": return "The sleep setting could not be restored, so the helper was kept. Check `pmset -g`."
        case "qaCopy": return "A QA copy never installs or removes the closed-lid helper."
        default: return "Helper \(result.reason) failed."
        }
    }

    /// Fixed command: this executable, a fixed flag, and one of two operation names. A path that could be
    /// misparsed by the shell or AppleScript is refused instead of escaped.
    nonisolated static func administratorCommand(executable: String, operation: String) -> String? {
        guard ["install", "uninstall"].contains(operation),
              !executable.isEmpty, !executable.contains(where: { "'\"\\\n\r".contains($0) }) else { return nil }
        return "'\(executable)' --helper-admin \(operation)"
    }

    /// The answer a QA copy gets for every install or removal: no administrator prompt, and the shared helper stays as it is.
    nonisolated static func refuseAdministratorCommand(_ operation: String) -> HelperOperationResult {
        HelperOperationResult(accepted: false, reason: "qaCopy", detail: nil)
    }

    nonisolated static func runWithAdministratorPrompt(operation: String) -> HelperOperationResult {
        guard let executable = Bundle.main.executablePath,
              let command = administratorCommand(executable: executable, operation: operation) else {
            return HelperOperationResult(accepted: false, reason: "helperSourceMissing", detail: nil)
        }
        let script = "do shell script \"\(command)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return HelperOperationResult(accepted: false, reason: "administratorRequired", detail: nil) }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if text.contains("User canceled") || text.contains("-128") {
            return HelperOperationResult(accepted: false, reason: "cancelled", detail: nil)
        }
        guard process.terminationStatus == 0 else {
            return HelperOperationResult(accepted: false, reason: reason(in: text) ?? "administratorRequired", detail: text)
        }
        return HelperOperationResult(accepted: true, reason: operation == "install" ? "installed" : "uninstalled", detail: nil)
    }

    nonisolated static func reason(in text: String) -> String? {
        // osascript wraps stderr as "…execution error: helper-admin: <reason> (1)".
        guard let range = text.range(of: "helper-admin:") else { return nil }
        let word = text[range.upperBound...].trimmingCharacters(in: .whitespaces).prefix { $0.isLetter || $0.isNumber }
        return word.isEmpty ? nil : String(word)
    }
}

/// Entry for `CamLid --helper-admin install|uninstall`, run as root by the administrator prompt before any UI starts.
public enum HelperAdminCommand {
    public static func runIfRequested(arguments: [String], appBundle: URL = Bundle.main.bundleURL) -> Int32? {
        guard let index = arguments.firstIndex(of: "--helper-admin"), index + 1 < arguments.count else { return nil }
        // Even run as root, a QA copy never changes the shared helper (see `StateLocations`).
        if StateLocations.qaRoot(inAppBundle: appBundle) != nil { print("helper-admin: qaCopy"); return 1 }
        let installer = HelperInstaller()
        let result: HelperOperationResult
        switch arguments[index + 1] {
        // Pressing Install is the explicit choice, so an identity file from an earlier install is moved aside
        // (kept as identity.json.previous and restored by uninstall), as `camlid helper install --replace-pins` does.
        case "install":
            // "Reinstall" after an app update: the pins and the installed helper belong to the old build, so remove
            // it (restoring the sleep setting first) and install the helper bundled with this build.
            if installer.status(appBundle: appBundle) != .notInstalled {
                let removed = installer.uninstall()
                guard removed.accepted || removed.reason == "notInstalled" else { result = removed; break }
            }
            result = installer.install(appBundle: appBundle, replacePins: true)
        case "uninstall": result = installer.uninstall()
        default: print("helper-admin: invalidOperation"); return 2
        }
        // stderr too: the administrator prompt reports only stderr when the command fails.
        let line = "helper-admin: \(result.reason)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        if !result.accepted { FileHandle.standardError.write(Data(line.utf8)) }
        return result.accepted ? 0 : 1
    }
}

extension HelperAdminCommand {
    /// Entry for `CamLid --helper-inspect`: one read-only XPC round trip proving the helper is reachable and
    /// that its pinned identity accepts this app. Prints the helper's state; never starts a session.
    public static func runInspectIfRequested(arguments: [String]) -> Int32? {
        guard arguments.contains("--helper-inspect") else { return nil }
        let transport = XPCPowerHoldTransport()
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var reply: HoldReply?
        Task.detached {
            reply = await transport.inspect()
            semaphore.signal()
        }
        semaphore.wait()
        transport.close()
        guard let reply else { print("helper-inspect: unreachable"); return 1 }
        print("helper-inspect: accepted=\(reply.accepted) state=\(reply.state) reason=\(reply.reason)")
        return reply.accepted ? 0 : 1
    }
}
