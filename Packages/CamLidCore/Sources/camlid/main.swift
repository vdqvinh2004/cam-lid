import CamLidCore
import CamLidCLI
import Foundation

// Thin executable: all logic lives in the CamLidCLI library for testability.
// argv here includes the program name, which Commands takes without it.
// The folders come from the copy this tool is inside (`StateLocations.forCLI`): a QA copy's tool reaches only its own
// folder, and only the installed app's tool reaches the owner's app. Without a folder, app-dependent commands report the
// app as unreachable (exit 4).
//
// F03 real plumbing: disk/stdin readers and an atomic disk writer are wired
// here, with no history store (honest unavailable, exit 4). Config and
// simulate read real files, event reads real stdin, and logs export writes
// real bytes atomically (refusing overwrite without --force).
let environment = ProcessInfo.processInfo.environment
let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
let locations = StateLocations.forCLI(executable: executable, controlOverride: environment["CAMLID_CONTROL_DIRECTORY"])
if locations == nil {
    FileHandle.standardError.write(Data("This copy of CamLid has no folder for this tool. Set CAMLID_CONTROL_DIRECTORY to a folder of its own.\n".utf8))
}
let result = Commands.runWithRealIO(
    argv: Array(CommandLine.arguments.dropFirst()),
    channel: locations.map { LocalControlChannel(directory: $0.control) as any IPCChannel },
    settingsURL: locations?.settingsURL,
    mayChangeHelper: locations?.isQA == false)
if !result.json.isEmpty { print(result.json) }   // `run` prints nothing itself: the command's output is its own
Foundation.exit(Int32(result.exitCode))
