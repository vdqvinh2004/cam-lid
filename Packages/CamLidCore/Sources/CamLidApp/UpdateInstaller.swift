import CamLidCore
import Foundation

/// What an install attempt reports: the checked app is handed to the swap script, or a named check failed.
enum UpdateInstallOutcome: Equatable {
    /// The swap script is running. Its process id lets a quit that stays cancelled stop it.
    case launched(Int32)
    case failed(String)
    var isLaunched: Bool { if case .launched = self { return true }; return false }
}

/// Spec 026: the install behind the Update button. A protocol, so the controller's rules can be tested without a download.
@MainActor protocol UpdateInstalling: AnyObject {
    /// True only when the running app is signed with a certificate the new release must match, and its folder is writable.
    var canInstall: Bool { get }
    func install(_ assets: UpdateAssets, version: String, current: ReleaseVersion,
                 completion: @escaping @MainActor (UpdateInstallOutcome) -> Void)
    /// Stops the swap script of an install whose quit stayed cancelled, so it cannot swap the app later without the user.
    func cancelLaunch(_ pid: Int32)
}

/// Installers without a script to stop need nothing here.
@MainActor extension UpdateInstalling {
    func cancelLaunch(_ pid: Int32) {}
}

/// The installer for builds that cannot install (tests, or a caller that never installs).
@MainActor final class NoUpdateInstaller: UpdateInstalling {
    var canInstall: Bool { false }
    func install(_ assets: UpdateAssets, version: String, current: ReleaseVersion,
                 completion: @escaping @MainActor (UpdateInstallOutcome) -> Void) {
        completion(.failed("updateNotWritable"))
    }
}

/// Spec 026: downloads one release, checks it (FR-004), puts the checked app beside the installed one, and starts the
/// script that swaps them once CamLid has quit (FR-005). Nothing is replaced before every check has passed.
@MainActor final class UpdateInstaller: UpdateInstalling {
    /// Downloads and the backup live under this folder: the real home, or the QA folder (spec 022 pattern).
    private let home: URL
    private let runner: any HelperCommandRunning
    private let installed: URL
    /// The arguments the new app starts with: the ones this app was started with, so a QA run stays in its folder.
    private let launchArguments: [String]

    init(home: URL, runner: any HelperCommandRunning = ProcessCommandRunner(), installed: URL = Bundle.main.bundleURL,
         launchArguments: [String]? = nil) {
        self.home = home
        self.runner = runner
        self.installed = installed
        self.launchArguments = launchArguments ?? Array(CommandLine.arguments.dropFirst())
    }

    /// The certificate the running app is signed with. Every release must be signed with it. Nil if the app is not validly signed.
    private lazy var pinnedLeaf: String? = {
        guard runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", installed.path]).status == 0 else { return nil }
        return CodeSignature.leaf(inDesignatedRequirement: runner.run("/usr/bin/codesign", ["-d", "-r-", installed.path]).output)
    }()

    var canInstall: Bool {
        pinnedLeaf != nil && installed.lastPathComponent == UpdatePackage.bundleName
            && FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path)
    }

    func install(_ assets: UpdateAssets, version: String, current: ReleaseVersion,
                 completion: @escaping @MainActor (UpdateInstallOutcome) -> Void) {
        guard let pinnedLeaf, canInstall else { completion(.failed("updateNotWritable")); return }
        let job = InstallJob(
            assets: assets, version: version, current: current, pinnedLeaf: pinnedLeaf, installed: installed,
            work: home.appendingPathComponent("Library/Caches/CamLid/Update/\(version)", isDirectory: true),
            backup: home.appendingPathComponent("Library/Application Support/CamLid/Update/previous/\(UpdatePackage.bundleName)"),
            arguments: launchArguments, runner: runner)
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) { await job.run() }.value
            completion(outcome)
        }
    }
    func cancelLaunch(_ pid: Int32) {
        guard pid > 0 else { return }
        _ = kill(pid, SIGTERM)
    }
}

/// One install attempt as plain values, so the file work runs off the main actor.
private struct InstallJob: Sendable {
    let assets: UpdateAssets
    let version: String
    let current: ReleaseVersion
    let pinnedLeaf: String
    let installed: URL
    let work: URL
    let backup: URL
    let arguments: [String]
    let runner: any HelperCommandRunning

    func run() async -> UpdateInstallOutcome {
        let fm = FileManager.default
        try? fm.removeItem(at: work)
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else {
            return .failed("updateStagingFailed")
        }
        // The zip and its checksum, from GitHub only, without cookies or an account.
        guard let zipData = await Self.fetch(assets.zipURL, limit: 100_000_000),
              let sumData = await Self.fetch(assets.checksumURL, limit: 4_096) else { return .failed("updateDownloadFailed") }
        let zip = work.appendingPathComponent(assets.zipURL.lastPathComponent)
        guard (try? zipData.write(to: zip)) != nil else { return .failed("updateStagingFailed") }
        // The zip must match the SHA-256 published with it (FR-004).
        guard let text = String(data: sumData, encoding: .utf8),
              let expected = UpdatePackage.expectedDigest(checksumFile: text, zipName: zip.lastPathComponent) else {
            return .failed(UpdatePackage.Failure.checksumUnreadable.rawValue)
        }
        guard UpdatePackage.digest(of: zip) == expected else { return .failed(UpdatePackage.Failure.checksumMismatch.rawValue) }
        // Unpack with ditto, then check the signature, identifier and version (FR-004).
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard runner.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]).status == 0 else {
            return .failed(UpdatePackage.Failure.unpackFailed.rawValue)
        }
        let app = unpacked.appendingPathComponent(UpdatePackage.bundleName)
        if let failure = UpdatePackage.verifyBundle(app, pinnedLeaf: pinnedLeaf, version: version, runner: runner) {
            return .failed(failure.rawValue)
        }
        guard let candidate = ReleaseVersion(version), current < candidate else { return .failed("updateNotNewer") }
        // Copy the checked app beside the installed one, so the swap is a rename on one volume, and check the copy as well.
        let partial = installed.deletingLastPathComponent().appendingPathComponent("CamLid-update.partial", isDirectory: true)
        try? fm.removeItem(at: partial)
        let staged = partial.appendingPathComponent(UpdatePackage.bundleName)
        guard (try? fm.createDirectory(at: partial, withIntermediateDirectories: true)) != nil,
              runner.run("/usr/bin/ditto", [app.path, staged.path]).status == 0 else {
            try? fm.removeItem(at: partial)
            return .failed("updateStagingFailed")
        }
        if let failure = UpdatePackage.verifyBundle(staged, pinnedLeaf: pinnedLeaf, version: version, runner: runner) {
            try? fm.removeItem(at: partial)
            return .failed(failure.rawValue)
        }
        // Hand over to the swap script. The app quits once this returns .launched.
        var launchedPID: Int32 = 0
        do {
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            let script = work.appendingPathComponent("install.sh")
            try UpdateSwap.script.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), installed.path,
                                 staged.path, backup.path] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            launchedPID = process.processIdentifier
        } catch {
            try? fm.removeItem(at: partial)
            return .failed("updateLaunchFailed")
        }
        return .launched(launchedPID)
    }

    private static func fetch(_ url: URL, limit: Int) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        do {
            let (data, response) = try await URLSession(configuration: configuration).data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= limit else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
