import Foundation
import Testing
@testable import CamLidCore

@Suite("State locations: each copy uses only its own folders")
struct StateLocationsTests {
    /// A temporary folder with an app bundle in it. The bundle names `bundleID` and, when given, a QA folder.
    private func makeApp(named name: String, in folder: URL, bundleID: String, qaRoot: URL? = nil) throws -> (app: URL, tool: URL) {
        let app = folder.appendingPathComponent(name + ".app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Helpers", isDirectory: true),
                                                withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": bundleID]
        if let qaRoot { info["CamLidQAStateDirectory"] = qaRoot.path }
        try (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return (app, contents.appendingPathComponent("Helpers/camlid"))
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-locations-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A QA copy's folders are all inside its own folder")
    func qaFoldersStayInside() {
        let root = URL(fileURLWithPath: "/tmp/camlid-qa-root-test", isDirectory: true)
        let qa = StateLocations.qa(root: root)
        for url in [qa.history, qa.control, qa.home, qa.settingsURL] {
            #expect(StateLocations.isFolder(url, insideOrEqualTo: root))
        }
        #expect(qa.isQA)
        #expect(!StateLocations.owner.isQA)
    }

    @Test("The installed app's tool uses the owner's folders")
    func installedAppKeepsOwnerFolders() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = try makeApp(named: "CamLid", in: folder, bundleID: StateLocations.ownerBundleIdentifier)
        let located = StateLocations.forCLI(executable: owner.tool, controlOverride: nil)
        #expect(located?.control == LocalControlChannel.defaultDirectory)
        #expect(located?.settingsURL == StateLocations.owner.settingsURL)
    }

    @Test("Another app's tool gets no folder, so it cannot reach the owner's app")
    func foreignAppGetsNothing() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = try makeApp(named: "Other", in: folder, bundleID: "com.example.other")
        #expect(StateLocations.forCLI(executable: other.tool, controlOverride: nil) == nil)
        #expect(StateLocations.forCLI(executable: other.tool, controlOverride: LocalControlChannel.defaultDirectory.path) == nil)
        #expect(StateLocations.forCLI(executable: other.tool, controlOverride: folder.appendingPathComponent("own").path) == nil)
    }

    @Test("A QA copy's tool uses its own folder and cannot move its control folder out of it")
    func qaCopyStaysInItsFolder() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let qaRoot = folder.appendingPathComponent("qa-root", isDirectory: true)
        let qa = try makeApp(named: "CamLid QA", in: folder, bundleID: "com.camlid.qa.rc", qaRoot: qaRoot)
        let own = StateLocations.forCLI(executable: qa.tool, controlOverride: nil)
        #expect(own?.control.path == qaRoot.appendingPathComponent("control", isDirectory: true).path)
        #expect(own?.settingsURL.path.hasPrefix(qaRoot.path + "/") == true)
        // The owner's socket and any folder outside the QA root are refused.
        #expect(StateLocations.forCLI(executable: qa.tool, controlOverride: LocalControlChannel.defaultDirectory.path) == nil)
        #expect(StateLocations.forCLI(executable: qa.tool, controlOverride: folder.appendingPathComponent("elsewhere").path) == nil)
        // A folder inside the QA root is allowed.
        let inside = qaRoot.appendingPathComponent("control-2", isDirectory: true)
        #expect(StateLocations.forCLI(executable: qa.tool, controlOverride: inside.path)?.control.path == inside.path)
    }

    @Test("A tool outside any app keeps the owner's folders, as the developer's own tool")
    func bareToolKeepsOwnerFolders() {
        let located = StateLocations.forCLI(executable: URL(fileURLWithPath: "/tmp/camlid-no-app/camlid"), controlOverride: nil)
        #expect(located?.control == LocalControlChannel.defaultDirectory)
    }

    @Test("The app runs as a QA copy when its bundle or its arguments name a QA folder")
    func appReadsItsQAFolder() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let qaRoot = folder.appendingPathComponent("qa-root", isDirectory: true)
        let qa = try makeApp(named: "CamLid QA", in: folder, bundleID: "com.camlid.qa.rc", qaRoot: qaRoot)
        let owner = try makeApp(named: "CamLid", in: folder, bundleID: StateLocations.ownerBundleIdentifier)
        #expect(StateLocations.forApp(bundle: qa.app, arguments: []).qaRoot?.path == qaRoot.path)
        #expect(StateLocations.forApp(bundle: owner.app, arguments: ["--qa-state-directory", qaRoot.path]).qaRoot?.path == qaRoot.path)
        #expect(StateLocations.forApp(bundle: owner.app, arguments: []).isQA == false)
    }
}
