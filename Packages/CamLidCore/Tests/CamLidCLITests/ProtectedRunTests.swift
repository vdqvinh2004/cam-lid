import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

/// Records the calls `camlid run` makes. Admission answers with the reply it is given; every other call answers with
/// an empty success, which is all `finish` needs.
private final class AdmissionChannel: IPCChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [AllowlistedCommand] = []
    private let admission: () throws -> Data

    init(admission: @escaping () throws -> Data) {
        self.admission = admission
    }

    var sent: [AllowlistedCommand] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        lock.lock()
        calls.append(command)
        lock.unlock()
        if command == .admitCommand { return try admission() }
        return try JSONEncoder().encode(CLIResult(json: "{\"schemaVersion\":1,\"accepted\":true}", exitCode: 0))
    }
}

private func admittedReply() throws -> Data {
    let receipt = "{\"id\":\"\(UUID().uuidString)\",\"sequence\":0,\"expiresAtMonotonic\":30}"
    return try JSONEncoder().encode(CLIResult(json: receipt, exitCode: 0))
}

@Suite("camlid run admission", .serialized)
struct ProtectedRunTests {
    @Test func aCommandNeedsTheSeparatorBeforeIt() {
        let result = Commands.runWithRealIO(argv: ["run", "/usr/bin/true"], channel: nil)
        #expect(result.exitCode == 2 && result.json.contains("missingSeparator"))
    }

    @Test func aSeparatorNeedsACommandAfterIt() {
        let result = Commands.runWithRealIO(argv: ["run", "--"], channel: nil)
        #expect(result.exitCode == 2 && result.json.contains("missingCommand"))
    }

    @Test func withoutTheAppNothingLaunches() {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-run-noapp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let result = Commands.runWithRealIO(argv: ["run", "--", "/usr/bin/touch", marker.path], channel: nil)
        #expect(result.exitCode == 4 && result.json.contains("appUnavailable"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func aRefusedAdmissionLaunchesNothing() {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-run-refused-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let channel = AdmissionChannel(admission: { throw IPCError.policyDenied("sessionNotStarted") })
        let result = Commands.runWithRealIO(argv: ["run", "--", "/usr/bin/touch", marker.path], channel: channel)
        #expect(result.exitCode == 3 && result.json.contains("sessionNotStarted"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(channel.sent == [.admitCommand])
    }

    @Test func aCommandRunsUnderItsAdmissionAndIsFinished() {
        let channel = AdmissionChannel(admission: admittedReply)
        let result = Commands.runWithRealIO(argv: ["run", "--", "/usr/bin/true"], channel: channel)
        #expect(result.exitCode == 0)
        #expect(channel.sent == [.admitCommand, .finishCommand])
    }

    @Test func theCommandsExitStatusIsReturned() {
        let channel = AdmissionChannel(admission: admittedReply)
        let result = Commands.runWithRealIO(argv: ["run", "--", "/bin/sh", "-c", "exit 7"], channel: channel)
        #expect(result.exitCode == 7)
        #expect(channel.sent == [.admitCommand, .finishCommand])
    }
}
