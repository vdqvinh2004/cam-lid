import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

private final class SleepRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let replies: [Data]
    private var index = 0
    private var stored: [(AllowlistedCommand, Data)] = []

    init(replies: [Data]) { self.replies = replies }

    func record(command: AllowlistedCommand, payload: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        stored.append((command, payload))
        guard replies.indices.contains(index) else { return nil }
        defer { index += 1 }
        return replies[index]
    }

    var requests: [(AllowlistedCommand, Data)] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private struct SleepFixtureChannel: IPCChannel {
    let recorder: SleepRequestRecorder
    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        guard let reply = recorder.record(command: command, payload: payload) else {
            throw IPCError.unavailable
        }
        return reply
    }
}

@Suite("Guarded sleep CLI") struct SleepCommandTests {
    @Test func noAppAndNoForce() {
        let dry = Commands.run(argv: ["sleep", "--dry-run", "--json"], channel: nil)
        #expect(dry.exitCode == 4 && dry.json.contains("appUnavailable"))
        let force = Commands.run(argv: ["sleep", "--force"], channel: nil)
        #expect(force.exitCode == 2 && force.json.contains("invalidOptions"))
    }

    @Test func dryRunAndRequestAreSeparateStructuredRevalidations() throws {
        let dryReply = try JSONEncoder().encode(CLIResult(
            json: "{\"eligible\":true,\"outcome\":\"notRequested\",\"blockers\":[]}", exitCode: 0))
        let requestReply = try JSONEncoder().encode(CLIResult(
            json: "{\"eligible\":false,\"outcome\":\"blocked\",\"blockers\":[\"backendUnverified\"]}", exitCode: 3))
        let recorder = SleepRequestRecorder(replies: [dryReply, requestReply])
        let channel = SleepFixtureChannel(recorder: recorder)

        let dry = Commands.run(argv: ["sleep", "--dry-run", "--json"], channel: channel)
        let request = Commands.run(argv: ["sleep", "--json"], channel: channel)
        #expect(dry.exitCode == 0 && dry.json.contains("notRequested"))
        #expect(request.exitCode == 3 && request.json.contains("backendUnverified"))

        let requests = recorder.requests
        #expect(requests.map(\.0) == [.sleep, .sleep])
        let dryOptions = try JSONDecoder().decode(CLIOptions.self, from: requests[0].1)
        let requestOptions = try JSONDecoder().decode(CLIOptions.self, from: requests[1].1)
        #expect(dryOptions.flags == ["dry-run": "true", "json": "true"])
        #expect(requestOptions.flags == ["json": "true"])
    }

    @Test func forceAndMalformedOptionsAreRejectedBeforeIPC() throws {
        let recorder = SleepRequestRecorder(replies: [])
        let channel = SleepFixtureChannel(recorder: recorder)
        let force = Commands.run(argv: ["sleep", "--force"], channel: channel)
        let malformed = Commands.run(argv: ["sleep", "--dry-run", "false"], channel: channel)
        #expect(force.exitCode == 2 && force.json.contains("invalidOptions"))
        #expect(malformed.exitCode == 2 && malformed.json.contains("invalidOptions"))
        #expect(recorder.requests.isEmpty)
    }
}
