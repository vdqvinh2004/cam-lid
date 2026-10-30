import Foundation
import AppKit

struct AgentInstallationSnapshot: Sendable, Equatable {
    let cliDetected: Set<String>
    let appDetected: Set<String>
    var allDetected: Set<String> { cliDetected.union(appDetected) }
}

/// Installation checks never execute a provider or infer its work state.
enum AgentCLIInstallation {
    static func detected(directories: [String]? = nil,
        orcaExecutable: String = OrcaPoller.bundledExecutable.path,
        applicationDetector: @escaping @Sendable (String) -> Bool = Self.applicationInstalled) -> Set<String> {
        snapshot(directories: directories, orcaExecutable: orcaExecutable,
                 applicationDetector: applicationDetector).allDetected
    }

    static func snapshot(directories: [String]? = nil,
        orcaExecutable: String = OrcaPoller.bundledExecutable.path,
        applicationDetector: @escaping @Sendable (String) -> Bool = Self.applicationInstalled) -> AgentInstallationSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = directories ?? Array(Set(
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.opencode/bin",
               home + "/.bun/bin", home + "/.npm-global/bin"]))
        var cli = Set<String>()
        var apps = Set<String>()

        for provider in AgentProviderCatalog.providers where provider.supportsDetection {
            if provider.cliNames.contains(where: { name in
                paths.contains { directory in isExecutable(directory + "/" + name) }
            }) {
                cli.insert(provider.id)
            }
            if provider.id == "orca", isExecutable(orcaExecutable) {
                cli.insert(provider.id)
            }
            if provider.applicationBundleIDs.contains(where: applicationDetector) {
                apps.insert(provider.id)
            }
        }
        return AgentInstallationSnapshot(cliDetected: cli, appDetected: apps)
    }

    private static func applicationInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }
}
