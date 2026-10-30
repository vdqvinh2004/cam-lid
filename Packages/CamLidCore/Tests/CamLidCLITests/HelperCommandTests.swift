import Foundation
import Testing
@testable import CamLidCLI
@testable import CamLidCore

private struct RecordingRunner: HelperCommandRunning {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) { (1, "") }
}

@Suite struct HelperCommandTests {
    private func installer() -> HelperInstaller {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-cli-\(UUID().uuidString)")
        return HelperInstaller(paths: HelperInstallPaths(root: root), runner: RecordingRunner(),
                               isAdministrator: false, applyOwnership: false)
    }

    @Test func statusIsReadOnlyAndMutatingCommandsNeedAdministrator() {
        let status = Commands.helperCommand(name: "helper status", options: CLIOptions(), installer: installer())
        #expect(status.exitCode == 0 && status.json.contains("\"status\":\"notInstalled\""))
        for name in ["helper install", "helper trust", "helper uninstall"] {
            let result = Commands.helperCommand(name: name, options: CLIOptions(), installer: installer())
            #expect(result.exitCode == 77 && result.json.contains("administratorRequired"))
        }
    }

    @Test func parsesTheHelperSubcommandAsOneName() {
        #expect(Commands.parse(argv: ["helper", "install", "--app", "/x"]).command == "helper install")
        var context = CommandContext(channel: nil)
        #expect(Commands.dispatch("helper", options: CLIOptions(), context: &context).exitCode == 2)
    }
}
