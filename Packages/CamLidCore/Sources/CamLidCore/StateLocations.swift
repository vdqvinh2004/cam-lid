import Foundation

/// The folders one CamLid copy uses: its settings and history, its command socket and its agent skill.
///
/// The installed app uses the owner's folders. A QA copy names one folder, in its Info.plist (`CamLidQAStateDirectory`)
/// or with `--qa-state-directory`, and every other folder follows from it. A QA copy cannot reach the owner's settings,
/// history, socket or skill, and `forCLI` applies the same rule to the command-line tool.
public struct StateLocations: Equatable, Sendable {
    public static let ownerBundleIdentifier = "com.camlid.CamLid"

    public let history: URL
    public let control: URL
    public let home: URL
    /// The QA folder this copy was built for; nil for the installed app.
    public let qaRoot: URL?

    public init(history: URL, control: URL, home: URL, qaRoot: URL?) {
        self.history = history
        self.control = control
        self.home = home
        self.qaRoot = qaRoot
    }

    public var isQA: Bool { qaRoot != nil }

    /// `preferences.json`: the app writes it, and `simulate --use-current-config` reads it.
    public var settingsURL: URL { history.appendingPathComponent(PersistedSettings.fileName) }

    /// The installed app's folders.
    public static var owner: StateLocations {
        StateLocations(history: FileHistoryStorage.defaultDirectory, control: LocalControlChannel.defaultDirectory,
                       home: FileManager.default.homeDirectoryForCurrentUser, qaRoot: nil)
    }

    /// Every folder of a QA copy, inside `root`.
    public static func qa(root: URL) -> StateLocations {
        StateLocations(history: root.appendingPathComponent("history", isDirectory: true),
                       control: root.appendingPathComponent("control", isDirectory: true),
                       home: root.appendingPathComponent("home", isDirectory: true), qaRoot: root)
    }

    /// The folders the app runs with: a QA folder from `--qa-state-directory` or the bundle, otherwise the owner's.
    public static func forApp(bundle: URL, arguments: [String]) -> StateLocations {
        if let index = arguments.firstIndex(of: "--qa-state-directory"), arguments.count > index + 1 {
            return .qa(root: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        }
        if let root = qaRoot(inAppBundle: bundle) { return .qa(root: root) }
        return .owner
    }

    /// The folders a command-line tool may use, from the copy it is inside (`CamLid.app/Contents/Helpers/camlid`).
    /// Only the installed app may use the owner's folders. A QA copy gets its own folder, and its control folder may be
    /// moved only inside that folder. Any other app gets nothing, so its commands cannot reach the owner's app. A tool
    /// outside any app is the developer's own and keeps the owner's folders. `controlOverride` is `CAMLID_CONTROL_DIRECTORY`.
    /// Nil means the tool may not use any folder.
    public static func forCLI(executable: URL, controlOverride: String?) -> StateLocations? {
        let base: StateLocations
        if let app = appBundle(containing: executable) {
            if let root = qaRoot(inAppBundle: app) {
                base = .qa(root: root)
            } else if isOwnerApp(app) {
                base = .owner
            } else {
                return nil
            }
        } else {
            base = .owner
        }
        guard let controlOverride else { return base }
        let folder = URL(fileURLWithPath: controlOverride, isDirectory: true)
        if let root = base.qaRoot, !isFolder(folder, insideOrEqualTo: root) { return nil }
        return StateLocations(history: base.history, control: folder, home: base.home, qaRoot: base.qaRoot)
    }

    /// The QA folder that an app bundle names in `CamLidQAStateDirectory`, or nil.
    public static func qaRoot(inAppBundle app: URL) -> URL? {
        guard let path = info(of: app)?["CamLidQAStateDirectory"] as? String else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func isOwnerApp(_ app: URL) -> Bool {
        (info(of: app)?["CFBundleIdentifier"] as? String) == ownerBundleIdentifier
    }

    /// The `.app` that contains `executable`, or nil when there is none.
    static func appBundle(containing executable: URL) -> URL? {
        var url = executable.resolvingSymlinksInPath().standardizedFileURL
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if url.pathExtension == "app",
               FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path) {
                return url
            }
        }
        return nil
    }

    static func isFolder(_ folder: URL, insideOrEqualTo root: URL) -> Bool {
        let parts = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return parts.count >= rootParts.count && Array(parts.prefix(rootParts.count)) == rootParts
    }

    private static func info(of app: URL) -> NSDictionary? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    }
}

/// Thrown by a step that a QA copy may not take, such as registering a login item for itself.
public struct QACopyRefusal: Error, Equatable {
    public init() {}
}
