import Foundation

/// Locations of the Standard-mode helper. `root` is "/" in production and a temporary directory in tests.
public struct HelperInstallPaths: Sendable {
    public static let helperLabel = "com.camlid.power-helper"
    public static let recoveryLabel = "com.camlid.power-recovery"

    public let root: URL
    public init(root: URL = URL(fileURLWithPath: "/")) { self.root = root }

    private func path(_ components: String...) -> URL {
        components.reduce(root) { $0.appendingPathComponent($1) }
    }
    public var helperBinary: URL { path("Library", "PrivilegedHelperTools", Self.helperLabel) }
    public var helperPlist: URL { path("Library", "LaunchDaemons", "\(Self.helperLabel).plist") }
    public var recoveryPlist: URL { path("Library", "LaunchDaemons", "\(Self.recoveryLabel).plist") }
    public var supportDirectory: URL { path("Library", "Application Support", "CamLidPowerHelper") }
    public var pinFile: URL { supportDirectory.appendingPathComponent("identity.json") }
}

public protocol HelperCommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)
}

public struct ProcessCommandRunner: HelperCommandRunning {
    public init() {}
    public func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (127, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

public enum HelperInstallStatus: Equatable, Sendable {
    case notInstalled
    case installed(loaded: Bool)
    /// The installed app no longer matches the pinned app identity (for example after a rebuild).
    case needsReauthorization
    /// The installed helper binary does not match its pin.
    case helperIdentityMismatch
    case partial(missing: [String])
}

public struct HelperOperationResult: Equatable, Sendable {
    public let accepted: Bool
    public let reason: String
    public let detail: String?
    public init(accepted: Bool, reason: String, detail: String?) {
        self.accepted = accepted; self.reason = reason; self.detail = detail
    }
    static func ok(_ reason: String, _ detail: String? = nil) -> Self { .init(accepted: true, reason: reason, detail: detail) }
    static func refused(_ reason: String, _ detail: String? = nil) -> Self { .init(accepted: false, reason: reason, detail: detail) }
}

/// Installs, removes and re-pins the Standard-mode LaunchDaemons. It needs administrator rights, accepts
/// no arbitrary command or path from a caller beyond the two bundle locations, and rolls back on failure.
public struct HelperInstaller: Sendable {
    public static let defaultAppBundle = URL(fileURLWithPath: "/Applications/CamLid.app")
    public static let bundledHelperPath = "Contents/Library/LaunchServices/camlid-power-helper"

    private let paths: HelperInstallPaths
    private let runner: any HelperCommandRunning
    private let isAdministrator: Bool
    private let applyOwnership: Bool

    public init(paths: HelperInstallPaths = HelperInstallPaths(), runner: any HelperCommandRunning = ProcessCommandRunner(),
                isAdministrator: Bool = geteuid() == 0, applyOwnership: Bool = true) {
        self.paths = paths
        self.runner = runner
        self.isAdministrator = isAdministrator
        self.applyOwnership = applyOwnership
    }

    // MARK: Status

    public func status(appBundle: URL = defaultAppBundle) -> HelperInstallStatus {
        let fm = FileManager.default
        let required: [(String, URL)] = [("helper", paths.helperBinary), ("daemonPlist", paths.helperPlist),
                                         ("recoveryPlist", paths.recoveryPlist), ("pins", paths.pinFile)]
        let missing = required.filter { !fm.fileExists(atPath: $0.1.path) }.map(\.0)
        if missing.count == required.count { return .notInstalled }
        if !missing.isEmpty { return .partial(missing: missing) }
        guard let pins = readPins() else { return .partial(missing: ["validPins"]) }
        guard let helperHash = cdHash(of: paths.helperBinary), helperHash == pins.helperCDHash else { return .helperIdentityMismatch }
        guard let appHash = cdHash(of: appBundle), appHash == pins.appCDHash else { return .needsReauthorization }
        return .installed(loaded: isServiceLoaded(HelperInstallPaths.helperLabel))
    }

    // MARK: Install

    /// `replacePins` lets the install move an existing `identity.json` from another CamLid install aside
    /// (kept as `identity.json.previous` and restored by `uninstall`); without it that file is never touched.
    public func install(appBundle: URL = defaultAppBundle, helperSource: URL? = nil,
                        replacePins: Bool = false) -> HelperOperationResult {
        guard isAdministrator else {
            return .refused("administratorRequired", "Run: sudo camlid helper install")
        }
        let source = helperSource ?? appBundle.appendingPathComponent(Self.bundledHelperPath)
        guard FileManager.default.isReadableFile(atPath: source.path), isRegularFile(source) else {
            return .refused("helperSourceMissing")
        }
        guard let helperHash = cdHash(of: source), let appHash = cdHash(of: appBundle) else {
            return .refused("signatureUnreadable", "Sign the app and helper before installing.")
        }
        guard helperHash != appHash else { return .refused("identitiesNotDistinct") }
        var movedPins = false
        switch status(appBundle: appBundle) {
        case .notInstalled:
            break
        case .partial(let missing) where Set(missing) == ["helper", "daemonPlist", "recoveryPlist"]:
            // Only an identity file exists: it belongs to an earlier install, not to this helper.
            guard replacePins else {
                return .refused("foreignPinsPresent", "An identity.json from another install exists. Re-run with --replace-pins to keep a backup and continue.")
            }
            guard !FileManager.default.fileExists(atPath: previousPinFile.path) else {
                return .refused("previousPinsBackupExists", previousPinFile.path)
            }
            movedPins = true
        case .installed where readPins()?.helperCDHash == helperHash && readPins()?.appCDHash == appHash:
            return .ok("alreadyInstalled")
        default:
            return .refused("alreadyInstalledDifferently", "Run: sudo camlid helper uninstall, then install; or helper trust after a rebuild.")
        }

        // A service already loaded under one of our labels is not ours (this install has no files yet):
        // never replace it, and never boot it out.
        for label in [HelperInstallPaths.helperLabel, HelperInstallPaths.recoveryLabel] where isServiceLoaded(label) {
            return .refused("labelInUse", "launchd already runs \(label) from an earlier install. Inspect it with `launchctl print system/\(label)` and remove it yourself if you intend to.")
        }

        var written: [URL] = []
        var bootstrapped: [String] = []
        func rollback() {
            // Only services this run started are stopped.
            for label in bootstrapped.reversed() { _ = runner.run("/bin/launchctl", ["bootout", "system/\(label)"]) }
            for url in written.reversed() { try? FileManager.default.removeItem(at: url) }
            if movedPins { try? FileManager.default.moveItem(at: previousPinFile, to: paths.pinFile) }
        }
        do {
            try makeDirectory(paths.supportDirectory, mode: 0o755)
            if movedPins {
                try FileManager.default.moveItem(at: paths.pinFile, to: previousPinFile)
            }
            try makeDirectory(paths.helperBinary.deletingLastPathComponent(), mode: 0o755)
            try makeDirectory(paths.helperPlist.deletingLastPathComponent(), mode: 0o755)
            try FileManager.default.copyItem(at: source, to: paths.helperBinary)
            written.append(paths.helperBinary)
            try secure(paths.helperBinary, mode: 0o755)
            try write(pinData(app: appHash, helper: helperHash), to: paths.pinFile, mode: 0o644)
            written.append(paths.pinFile)
            try write(Self.plist(label: HelperInstallPaths.helperLabel, program: paths.helperBinary.path,
                                 argument: "--standard-v1", resident: true), to: paths.helperPlist, mode: 0o644)
            written.append(paths.helperPlist)
            try write(Self.plist(label: HelperInstallPaths.recoveryLabel, program: paths.helperBinary.path,
                                 argument: "--recover-v1", resident: false), to: paths.recoveryPlist, mode: 0o644)
            written.append(paths.recoveryPlist)
        } catch {
            rollback()
            return .refused("installFailed", String(describing: error))
        }
        for (plist, label) in [(paths.helperPlist, HelperInstallPaths.helperLabel), (paths.recoveryPlist, HelperInstallPaths.recoveryLabel)] {
            let result = runner.run("/bin/launchctl", ["bootstrap", "system", plist.path])
            guard result.status == 0 else {
                rollback()
                return .refused("bootstrapFailed", result.output)
            }
            bootstrapped.append(label)
        }
        return .ok("installed")
    }

    // MARK: Trust (re-pin after a rebuild)

    public func trust(appBundle: URL = defaultAppBundle) -> HelperOperationResult {
        guard isAdministrator else { return .refused("administratorRequired", "Run: sudo camlid helper trust") }
        guard FileManager.default.fileExists(atPath: paths.helperBinary.path) else { return .refused("notInstalled") }
        guard let helperHash = cdHash(of: paths.helperBinary), let appHash = cdHash(of: appBundle) else {
            return .refused("signatureUnreadable")
        }
        guard helperHash != appHash else { return .refused("identitiesNotDistinct") }
        do { try write(pinData(app: appHash, helper: helperHash), to: paths.pinFile, mode: 0o644) }
        catch { return .refused("trustFailed", String(describing: error)) }
        let kick = runner.run("/bin/launchctl", ["kickstart", "-k", "system/\(HelperInstallPaths.helperLabel)"])
        return kick.status == 0 ? .ok("trusted") : .ok("trustedRestartPending", kick.output)
    }

    // MARK: Uninstall

    /// Restores an owned sleep policy first; refuses to remove the daemons while that is unresolved unless forced.
    public func uninstall(force: Bool = false) -> HelperOperationResult {
        guard isAdministrator else { return .refused("administratorRequired", "Run: sudo camlid helper uninstall") }
        let fm = FileManager.default
        guard [paths.helperBinary, paths.helperPlist, paths.recoveryPlist].contains(where: { fm.fileExists(atPath: $0.path) }) else {
            return .refused("notInstalled", fm.fileExists(atPath: paths.pinFile.path)
                ? "Only an identity.json from another install is present; nothing of this helper to remove." : nil)
        }
        if FileManager.default.fileExists(atPath: paths.helperBinary.path) {
            let release = runner.run(paths.helperBinary.path, ["--release-v1"])
            if release.status != 0 && !force {
                return .refused("restoreUnresolved", "The sleep policy could not be restored; check `pmset -g`. Re-run with --force to remove anyway.")
            }
        }
        _ = runner.run("/bin/launchctl", ["bootout", "system/\(HelperInstallPaths.recoveryLabel)"])
        _ = runner.run("/bin/launchctl", ["bootout", "system/\(HelperInstallPaths.helperLabel)"])
        var failed: [String] = []
        for url in [paths.recoveryPlist, paths.helperPlist, paths.pinFile, paths.helperBinary] {
            do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
            catch { failed.append(url.lastPathComponent) }
        }
        // Put back an identity file that install moved aside, and never delete the support directory
        // itself: it may hold files from other installs. Remove it only when it is empty.
        if fm.fileExists(atPath: previousPinFile.path) {
            do { try fm.moveItem(at: previousPinFile, to: paths.pinFile) } catch { failed.append(previousPinFile.lastPathComponent) }
        }
        if (try? fm.contentsOfDirectory(atPath: paths.supportDirectory.path))?.isEmpty == true {
            try? fm.removeItem(at: paths.supportDirectory)
        }
        if !failed.isEmpty { return .refused("removeIncomplete", failed.joined(separator: ", ")) }
        return .ok("uninstalled", "Journal under /private/var/db/CamLidPowerHelper and logs under /var/log/com.camlid.power-*.log were left in place.")
    }

    // MARK: Helpers

    /// Whether launchd currently has a service under the helper label, whoever installed it.
    public func serviceLoaded() -> Bool { isServiceLoaded(HelperInstallPaths.helperLabel) }

    public func isServiceLoaded(_ label: String) -> Bool {
        runner.run("/bin/launchctl", ["print", "system/\(label)"]).status == 0
    }

    private var previousPinFile: URL { paths.supportDirectory.appendingPathComponent("identity.json.previous") }

    static func plist(label: String, program: String, argument: String, resident: Bool) -> Data {
        let log = "/var/log/\(label).log"
        var dict: [String: Any] = ["Label": label, "Program": program, "ProgramArguments": [program, argument],
                                   "RunAtLoad": true, "StandardOutPath": log, "StandardErrorPath": log]
        if resident {
            dict["MachServices"] = [label: true]
            dict["KeepAlive"] = true
            dict["ThrottleInterval"] = 10
            dict["ProcessType"] = "Adaptive"
        } else {
            dict["StartInterval"] = 15
            dict["ProcessType"] = "Background"
        }
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    static func parseCDHash(_ output: String) -> String? {
        let hashes = output.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("CDHash=") else { return nil }
            return String(line.dropFirst("CDHash=".count))
        }
        guard hashes.count == 1, let hash = hashes.first, hash.count == 40,
              hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return hash
    }

    private func cdHash(of url: URL) -> String? {
        let verify = runner.run("/usr/bin/codesign", ["--verify", "--strict", url.path])
        guard verify.status == 0 else { return nil }
        let info = runner.run("/usr/bin/codesign", ["-dvvv", url.path])
        return info.status == 0 ? Self.parseCDHash(info.output) : nil
    }

    private func readPins() -> (appCDHash: String, helperCDHash: String)? {
        guard let data = try? Data(contentsOf: paths.pinFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1, let app = object["appCDHash"] as? String,
              let helper = object["helperCDHash"] as? String, app != helper else { return nil }
        return (app, helper)
    }

    private func pinData(app: String, helper: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "appCDHash": app, "helperCDHash": helper],
                                   options: [.prettyPrinted, .sortedKeys])
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func makeDirectory(_ url: URL, mode: Int) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: mode])
        try secure(url, mode: mode)
    }

    private func write(_ data: Data, to url: URL, mode: Int) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).new")
        try? FileManager.default.removeItem(at: temporary)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                             attributes: [.posixPermissions: mode]) else { throw CocoaError(.fileWriteUnknown) }
        try secure(temporary, mode: mode)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    private func secure(_ url: URL, mode: Int) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: mode]
        if applyOwnership { attributes[.ownerAccountID] = 0; attributes[.groupOwnerAccountID] = 0 }
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
}
