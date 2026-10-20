import Foundation

/// Installation checks never execute a provider or infer its work state.
enum AgentCLIInstallation {
    static func detected(directories: [String]? = nil,
        orcaExecutable: String = OrcaPoller.bundledExecutable.path) -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = directories ?? Array(Set(
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.opencode/bin",
               home + "/.bun/bin", home + "/.npm-global/bin"]))
        return Set(AgentBadgeState.providers.filter { provider in
            let names = provider == "orca" ? ["orca", "orca-cli"] : [provider]
            return paths.contains { directory in
                names.contains { isExecutable(directory + "/" + $0) }
            } || (provider == "orca" && isExecutable(orcaExecutable))
        })
    }

    private static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }
}
