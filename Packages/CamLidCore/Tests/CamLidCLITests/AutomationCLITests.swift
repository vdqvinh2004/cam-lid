import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

@Suite("M8 diagnostic contracts") struct AutomationCLITests {
    @Test func diagnosisRequiresAppWithoutLaunchingIt() throws {
        let result = Commands.run(argv: ["diagnose", "--json"], channel: nil)
        #expect(result.exitCode == 4)
        #expect(result.json.contains("appUnavailable"))
        for coverage: DiagnosticCoverage in [.partial, .unavailable] {
            let report = DiagnosticSnapshot(coverage: ["userAssertions": coverage], errors: ["fixturePartial"])
            let reply = Commands.run(argv: ["diagnose", "--json"], channel: DiagnosticFixtureChannel(snapshot: report))
            #expect(reply.exitCode == (coverage == .unavailable ? 4 : 0))
            #expect(reply.json.contains(coverage.rawValue) && reply.json.contains("activeSessionMode"))
        }
        #expect(Commands.run(argv: ["diagnose", "--force"], channel: nil).exitCode == 2)
    }
    @Test func diagnosticExportBoundsAndRedactsIdentity() throws {
        let rows = (0..<300).map { DiagnosticBlocker(id: "42-\($0)", type: "PreventUserIdleDisplaySleep", effect: .displayIdle,
            source: "IOKit", owner: "PRIVATE_OWNER", pid: 42, explanation: SleepEffect.displayIdle.title) }
        let snapshot = DiagnosticSnapshot(coverage: ["userAssertions": .complete], configuredMode: .timed, blockers: rows)
        let bytes = try snapshot.boundedJSON()
        #expect(bytes.count <= 28_000)
        let cliReply = try JSONEncoder().encode(CLIResult(json: String(decoding: bytes, as: UTF8.self), exitCode: 0))
        let wire = try JSONEncoder().encode(DiagnosticTestWireReply(payload: cliReply))
        #expect(wire.count <= PolicyLimits.maxEventBytes)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("PRIVATE_OWNER") && !text.contains("42-"))
        #expect(text.contains("partial") && text.contains("Truncated"))
        #expect(snapshot.activeSessionMode == nil && snapshot.protection == .notRequested)
        let json = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        #expect(json["activeSessionMode"] is NSNull)
        let unavailable = DiagnosticSnapshot(coverage: ["userAssertions": .unavailable])
        #expect(!unavailable.hasCoverage)
        #expect(DiagnosticSnapshot(coverage: ["userAssertions": .partial]).hasCoverage)
    }
}

private struct DiagnosticTestWireReply: Encodable { let payload: Data }

private struct DiagnosticFixtureChannel: IPCChannel {
    let snapshot: DiagnosticSnapshot
    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        #expect(command == .diagnose && payload.isEmpty)
        let data = try snapshot.boundedJSON()
        return try JSONEncoder().encode(CLIResult(json: String(decoding: data, as: UTF8.self), exitCode: snapshot.hasCoverage ? 0 : 4))
    }
}
