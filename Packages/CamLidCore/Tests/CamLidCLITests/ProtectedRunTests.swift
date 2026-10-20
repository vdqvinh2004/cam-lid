import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

@Suite("Legacy command wrapping excluded", .serialized)
struct ProtectedRunTests {
    @Test(arguments: [[], ["--keep-awake"]])
    func neitherProtectedNorUnprotectedRunLaunches(_ options: [String]) {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-no-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let result = Commands.runWithRealIO(argv: ["run"] + options + ["--", "/usr/bin/touch", marker.path], channel: nil)
        #expect(result.exitCode == 3 && result.json.contains("externalObservationOnly"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(arguments: [["run"], ["run", "--", "/no/such/command"], ["run", "--keep-awake=false", "--", "/bin/sh", "-c", "exit 0"]])
    func refusalPrecedesCommandValidationOrExecution(_ arguments: [String]) {
        let result = Commands.runWithRealIO(argv: arguments, channel: nil)
        #expect(result.exitCode == 3 && result.json.contains("externalObservationOnly"))
    }
}
