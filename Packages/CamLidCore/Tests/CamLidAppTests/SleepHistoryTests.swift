import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("M8 sleep request history", .serialized)
struct SleepHistoryTests {
    @Test @MainActor func dryRunDoesNotWriteButActualRefusalRecordsItsBlockers() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let dryRun = try JSONEncoder().encode(CLIOptions(flags: ["dry-run": "true"]))
        _ = try app.handleControl(.sleep, payload: dryRun)
        let before = try await exportedRecords(app)
        #expect(before.isEmpty)
        #expect(throws: IPCError.self) {
            try app.handleControl(.sleep, payload: JSONEncoder().encode(CLIOptions(flags: ["force": "true"])))
        }
        #expect(try await exportedRecords(app).isEmpty)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.sleep, payload: Data()))
        let decision = try JSONDecoder().decode(GuardedSleepDecision.self, from: Data(reply.json.utf8))
        #expect(reply.exitCode == 3 && decision.outcome == "blocked")
        let records = try await exportedRecords(app)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record["schemaVersion"] as? Int == 1)
        #expect(record["category"] as? String == "stateTransition")
        #expect(record["reasonCodes"] as? [String] == ["sleepBlocked"] + decision.blockers)
        #expect(ActivityPresentation.readableReason("sleepBlocked") == "Sleep request blocked")
    }

    @MainActor private func exportedRecords(_ app: AppCoordinator) async throws -> [[String: Any]] {
        let data = try await app.handleControlAsync(.logsExport, payload: Data(), deadline: ContinuousTime.now + 2)
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}
