import CamLidCore
import CamLidCLI
import Foundation

// Thin executable: all logic lives in the CamLidCLI library for testability.
// argv here includes the program name, which Commands takes without it.
// A nil channel means the app is unreachable (app-dependent commands exit 4);
// the real same-user channel arrives with the CamLidApp IPC half (T005).
//
// F03 real plumbing: disk/stdin readers and an atomic disk writer are wired
// here, with no history store (honest unavailable, exit 4). Config and
// simulate read real files, event reads real stdin, and logs export writes
// real bytes atomically (refusing overwrite without --force).
let controlDirectory = ProcessInfo.processInfo.environment["CAMLID_CONTROL_DIRECTORY"].map { URL(fileURLWithPath: $0) }
let result = Commands.runWithRealIO(
    argv: Array(CommandLine.arguments.dropFirst()), channel: LocalControlChannel(directory: controlDirectory ?? LocalControlChannel.defaultDirectory))
print(result.json)
Foundation.exit(Int32(result.exitCode))
