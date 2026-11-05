import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

private final class ObservationBoundaryChannel: IPCChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [AllowlistedCommand] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return commands.count }
    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        lock.lock(); defer { lock.unlock() }; commands.append(command)
        throw IPCError.unavailable
    }
}

@Suite("Third-person CLI boundary", .serialized)
struct ExternalObservationBoundaryTests {
    @Test(arguments: ["event", "bridge"])
    func legacyEntryPointsRefuseBeforeReadingOrContactingAnything(_ name: String) throws {
        let channel = ObservationBoundaryChannel()
        var context = CommandContext(channel: channel, stdinData: Data("PRIVATE".utf8))
        let virtual = Commands.dispatch(name, options: CLIOptions(), context: &context)
        let real = Commands.runWithRealIO(argv: [name], channel: channel)
        for reply in [virtual, real] {
            #expect(reply.exitCode == 3 && reply.json.contains("externalObservationOnly"))
            #expect(!reply.json.contains("PRIVATE"))
        }
        #expect(channel.count == 0)
    }

    @Test func runCannotLaunchWithoutTheApp() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-no-wrapper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let result = Commands.runWithRealIO(argv: ["run", "--", "/usr/bin/touch", marker.path], channel: nil)
        #expect(result.exitCode == 4 && result.json.contains("appUnavailable"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
}
