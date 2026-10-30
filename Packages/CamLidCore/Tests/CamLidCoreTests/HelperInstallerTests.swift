import Foundation
import Testing
@testable import CamLidCore

private final class FakeRunner: HelperCommandRunning, @unchecked Sendable {
    var hashes: [String: String] = [:]          // path suffix -> cdhash
    var failing: Set<String> = []               // "executable arg0" prefixes that exit 1
    var calls: [String] = []
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let line = ([executable] + arguments).joined(separator: " ")
        calls.append(line)
        if failing.contains(where: { line.hasPrefix($0) }) { return (1, "failed") }
        if executable == "/usr/bin/codesign", arguments.first == "-dvvv", let path = arguments.last {
            guard let hash = hashes.first(where: { path.hasSuffix($0.key) })?.value else { return (1, "") }
            return (0, "Identifier=x\nCDHash=\(hash)\n")
        }
        if executable == "/usr/bin/codesign", let path = arguments.last {
            return hashes.contains(where: { path.hasSuffix($0.key) }) ? (0, "") : (1, "")
        }
        return (0, "")
    }
}

private struct Rig {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-installer-\(UUID().uuidString)")
    let runner = FakeRunner()
    let app: URL
    let source: URL
    init() throws {
        app = root.appendingPathComponent("CamLid.app")
        source = app.appendingPathComponent(HelperInstaller.bundledHelperPath)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: source)
        runner.hashes = ["CamLid.app": String(repeating: "a", count: 40), "camlid-power-helper": String(repeating: "b", count: 40),
                         "com.camlid.power-helper": String(repeating: "b", count: 40)]
    }
    var paths: HelperInstallPaths { HelperInstallPaths(root: root.appendingPathComponent("fs")) }
    func installer(admin: Bool = true) -> HelperInstaller {
        HelperInstaller(paths: paths, runner: runner, isAdministrator: admin, applyOwnership: false)
    }
}

@Suite struct HelperInstallerTests {
    @Test func refusesWithoutAdministratorAndChangesNothing() throws {
        let rig = try Rig()
        let result = rig.installer(admin: false).install(appBundle: rig.app)
        #expect(!result.accepted && result.reason == "administratorRequired")
        #expect(!FileManager.default.fileExists(atPath: rig.paths.helperBinary.path))
        #expect(rig.runner.calls.isEmpty)
    }

    @Test func installsFilesPinsAndBootstrapsBothDaemons() throws {
        let rig = try Rig()
        let result = rig.installer().install(appBundle: rig.app)
        #expect(result.accepted && result.reason == "installed")
        let fm = FileManager.default
        for url in [rig.paths.helperBinary, rig.paths.helperPlist, rig.paths.recoveryPlist, rig.paths.pinFile] {
            #expect(fm.fileExists(atPath: url.path))
        }
        let pins = try JSONSerialization.jsonObject(with: Data(contentsOf: rig.paths.pinFile)) as? [String: Any]
        #expect(pins?["appCDHash"] as? String == String(repeating: "a", count: 40))
        #expect(pins?["helperCDHash"] as? String == String(repeating: "b", count: 40))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: rig.paths.helperPlist), format: nil) as? [String: Any]
        #expect(plist?["ProgramArguments"] as? [String] == [rig.paths.helperBinary.path, "--standard-v1"])
        let recovery = try PropertyListSerialization.propertyList(from: Data(contentsOf: rig.paths.recoveryPlist), format: nil) as? [String: Any]
        #expect(recovery?["ProgramArguments"] as? [String] == [rig.paths.helperBinary.path, "--recover-v1"])
        #expect(rig.runner.calls.filter { $0.hasPrefix("/bin/launchctl bootstrap system") }.count == 2)
    }

    @Test func installIsIdempotentAndRefusesADifferentInstall() throws {
        let rig = try Rig()
        #expect(rig.installer().install(appBundle: rig.app).accepted)
        #expect(rig.installer().install(appBundle: rig.app).reason == "alreadyInstalled")
        rig.runner.hashes["CamLid.app"] = String(repeating: "c", count: 40)
        #expect(rig.installer().install(appBundle: rig.app).reason == "alreadyInstalledDifferently")
        #expect(rig.installer().status(appBundle: rig.app) == .needsReauthorization)
    }

    @Test func bootstrapFailureRollsBackEverything() throws {
        let rig = try Rig()
        rig.runner.failing = ["/bin/launchctl bootstrap"]
        let result = rig.installer().install(appBundle: rig.app)
        #expect(!result.accepted && result.reason == "bootstrapFailed")
        #expect(rig.installer().status(appBundle: rig.app) == .notInstalled)
    }

    @Test func refusesUnsignedOrIndistinctIdentities() throws {
        let rig = try Rig()
        rig.runner.hashes = [:]
        #expect(rig.installer().install(appBundle: rig.app).reason == "signatureUnreadable")
        rig.runner.hashes = ["CamLid.app": String(repeating: "a", count: 40), "camlid-power-helper": String(repeating: "a", count: 40)]
        #expect(rig.installer().install(appBundle: rig.app).reason == "identitiesNotDistinct")
    }

    @Test func trustRepinsAfterARebuildAndRestartsTheHelper() throws {
        let rig = try Rig()
        #expect(rig.installer().install(appBundle: rig.app).accepted)
        rig.runner.hashes["CamLid.app"] = String(repeating: "c", count: 40)
        #expect(rig.installer().status(appBundle: rig.app) == .needsReauthorization)
        #expect(rig.installer().trust(appBundle: rig.app).reason == "trusted")
        #expect(rig.installer().status(appBundle: rig.app) == .installed(loaded: true))
        #expect(rig.runner.calls.contains { $0.hasPrefix("/bin/launchctl kickstart -k system/com.camlid.power-helper") })
    }

    @Test func aReplacedHelperBinaryIsReportedAsMismatch() throws {
        let rig = try Rig()
        #expect(rig.installer().install(appBundle: rig.app).accepted)
        rig.runner.hashes["com.camlid.power-helper"] = String(repeating: "d", count: 40)
        rig.runner.hashes["camlid-power-helper"] = nil
        #expect(rig.installer().status(appBundle: rig.app) == .helperIdentityMismatch)
    }

    @Test func uninstallReleasesThePolicyBeforeRemovingAnything() throws {
        let rig = try Rig()
        #expect(rig.installer().install(appBundle: rig.app).accepted)
        rig.runner.calls = []
        let result = rig.installer().uninstall()
        #expect(result.accepted && result.reason == "uninstalled")
        #expect(rig.runner.calls.first?.hasSuffix("--release-v1") == true)
        #expect(rig.installer().status(appBundle: rig.app) == .notInstalled)
    }

    @Test func uninstallRefusesWhileTheRestoreIsUnresolvedUnlessForced() throws {
        let rig = try Rig()
        #expect(rig.installer().install(appBundle: rig.app).accepted)
        rig.runner.failing = [rig.paths.helperBinary.path]
        let refused = rig.installer().uninstall()
        #expect(!refused.accepted && refused.reason == "restoreUnresolved")
        #expect(FileManager.default.fileExists(atPath: rig.paths.helperBinary.path))
        #expect(rig.installer().uninstall(force: true).accepted)
    }

    @Test func cdHashParserAcceptsOnlyOneLowercaseSha1() {
        let hash = String(repeating: "ab", count: 20)
        #expect(HelperInstaller.parseCDHash("CDHash=\(hash)\n") == hash)
        #expect(HelperInstaller.parseCDHash("CDHash=\(hash)\nCDHash=\(hash)\n") == nil)
        #expect(HelperInstaller.parseCDHash("CDHash=bad") == nil)
        #expect(HelperInstaller.parseCDHash("CDHash=\(hash.uppercased())") == nil)
    }
}


@Suite struct HelperInstallerForeignFilesTests {
    private func plantForeignFiles(_ rig: Rig) throws -> (pins: URL, evidence: URL) {
        let support = rig.paths.supportDirectory
        try FileManager.default.createDirectory(at: support.appendingPathComponent("once-scope"), withIntermediateDirectories: true)
        let evidence = support.appendingPathComponent("once-scope/consumed.json")
        try Data("evidence".utf8).write(to: evidence)
        try Data(#"{"version":1,"appCDHash":"old"}"#.utf8).write(to: rig.paths.pinFile)
        return (rig.paths.pinFile, evidence)
    }

    @Test func foreignPinsAreNeverOverwrittenWithoutExplicitConsent() throws {
        let rig = try Rig()
        let (pins, _) = try plantForeignFiles(rig)
        #expect(rig.installer().status(appBundle: rig.app) == .partial(missing: ["helper", "daemonPlist", "recoveryPlist"]))
        let result = rig.installer().install(appBundle: rig.app)
        #expect(!result.accepted && result.reason == "foreignPinsPresent")
        #expect(try String(contentsOf: pins, encoding: .utf8).contains("\"old\""))
        #expect(!rig.runner.calls.contains { $0.hasPrefix("/bin/launchctl") })
    }

    @Test func replacingPinsKeepsABackupAndUninstallRestoresItAndLeavesOtherFiles() throws {
        let rig = try Rig()
        let (pins, evidence) = try plantForeignFiles(rig)
        #expect(rig.installer().install(appBundle: rig.app, replacePins: true).accepted)
        let backup = rig.paths.supportDirectory.appendingPathComponent("identity.json.previous")
        #expect(try String(contentsOf: backup, encoding: .utf8).contains("\"old\""))
        #expect(try String(contentsOf: pins, encoding: .utf8).contains("appCDHash") && !(try String(contentsOf: pins, encoding: .utf8).contains("\"old\"")))

        #expect(rig.installer().uninstall().accepted)
        #expect(try String(contentsOf: pins, encoding: .utf8).contains("\"old\""))          // original restored
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(FileManager.default.fileExists(atPath: evidence.path))                      // untouched
        #expect(FileManager.default.fileExists(atPath: rig.paths.supportDirectory.path))
    }

    @Test func uninstallWithOnlyForeignPinsRemovesNothing() throws {
        let rig = try Rig()
        let (pins, evidence) = try plantForeignFiles(rig)
        let result = rig.installer().uninstall()
        #expect(!result.accepted && result.reason == "notInstalled")
        #expect(FileManager.default.fileExists(atPath: pins.path) && FileManager.default.fileExists(atPath: evidence.path))
    }

    @Test func aFailedInstallRestoresTheMovedPins() throws {
        let rig = try Rig()
        let (pins, _) = try plantForeignFiles(rig)
        rig.runner.failing = ["/bin/launchctl bootstrap"]
        let result = rig.installer().install(appBundle: rig.app, replacePins: true)
        #expect(!result.accepted && result.reason == "bootstrapFailed")
        #expect(try String(contentsOf: pins, encoding: .utf8).contains("\"old\""))
    }

    @Test func theSupportDirectoryIsRemovedOnlyWhenEmpty() throws {
        let rig = try Rig()
        #expect(rig.installer().install(appBundle: rig.app).accepted)
        #expect(rig.installer().uninstall().accepted)
        #expect(!FileManager.default.fileExists(atPath: rig.paths.supportDirectory.path))
    }
}
