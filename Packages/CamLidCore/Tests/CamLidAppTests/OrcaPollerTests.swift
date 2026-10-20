import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("Orca installed-schema compatibility")
struct OrcaPollerTests {
    let status = Data(#"{"ok":true,"result":{"target":{"kind":"local"},"runtime":{"appVersion":"1.4.220","reachable":true,"runtimeId":"test"}}}"#.utf8)
    @Test func metadataOnlyLocalRows() throws {
        let worktrees = Data(#"{"ok":true,"_meta":{"runtimeId":"test"},"result":{"truncated":false,"worktrees":[{"hostId":"local","agents":[{"paneKey":"pane","state":"done","prompt":"discard","toolInput":"secret"}]},{"hostId":"remote","agents":[{"paneKey":"foreign","state":"working"}]}]}}"#.utf8)
        let rows = try OrcaPoller.decode(status: status, worktrees: worktrees)
        #expect(rows.count == 1)
        #expect(rows.first?.agentState == "idle")
        #expect(rows.first?.host == "local")
    }
    @Test func truncationRejectsRegardlessOfVersion() throws {
        let worktrees = Data(#"{"ok":true,"_meta":{"runtimeId":"test"},"result":{"truncated":true,"worktrees":[]}}"#.utf8)
        #expect(throws: (any Error).self) { try OrcaPoller.decode(status: status, worktrees: worktrees) }
    }
    @Test(arguments: ["1.4.220", "1.4.227", "1.5.0", "2.0.0", "garbage", ""])
    func anyVersionDecodesWhenSchemaHolds(_ version: String) throws {
        let worktrees = Data(#"{"ok":true,"_meta":{"runtimeId":"test"},"result":{"truncated":false,"worktrees":[]}}"#.utf8)
        let drifted = Data(String(decoding: status, as: UTF8.self).replacingOccurrences(of: "1.4.220", with: version).utf8)
        #expect(try OrcaPoller.decode(status: drifted, worktrees: worktrees).isEmpty)
    }
    @Test(arguments: ["1.4.226", "9.9.9"])
    func brokenSchemaRejectsRegardlessOfVersion(_ version: String) throws {
        let goodTrees = Data(#"{"ok":true,"_meta":{"runtimeId":"test"},"result":{"truncated":false,"worktrees":[]}}"#.utf8)
        let dead = Data("{\"ok\":true,\"result\":{\"target\":{\"kind\":\"local\"},\"runtime\":{\"appVersion\":\"\(version)\",\"reachable\":false,\"runtimeId\":\"test\"}}}".utf8)
        #expect(throws: (any Error).self) { try OrcaPoller.decode(status: dead, worktrees: goodTrees) }
        let remote = Data("{\"ok\":true,\"result\":{\"target\":{\"kind\":\"remote\"},\"runtime\":{\"appVersion\":\"\(version)\",\"reachable\":true,\"runtimeId\":\"test\"}}}".utf8)
        #expect(throws: (any Error).self) { try OrcaPoller.decode(status: remote, worktrees: goodTrees) }
        let cut = Data(#"{"ok":true,"_meta":{"runtimeId":"test"},"result":{"truncated":true,"worktrees":[]}}"#.utf8)
        let drifted = Data(String(decoding: status, as: UTF8.self).replacingOccurrences(of: "1.4.220", with: version).utf8)
        #expect(throws: (any Error).self) { try OrcaPoller.decode(status: drifted, worktrees: cut) }
    }
    @Test func userMessagesNeverLeakCaseNames() {
        for error: OrcaPollError in [.unavailable, .timeout, .tooLarge, .remote, .invalid] {
            #expect(!error.userMessage.contains("OrcaPollError"))
        }
    }
    @Test func finishingOneHostedPaneDoesNotCompleteAnother() throws {
        var runtime = RuntimeAgentStore()
        var sequences: [String: Int] = [:]
        func snapshot(_ firstState: String) throws -> [OrcaWorktreeRow] {
            let bytes = Data("{\"ok\":true,\"_meta\":{\"runtimeId\":\"test\"},\"result\":{\"truncated\":false,\"worktrees\":[{\"hostId\":\"local\",\"agents\":[{\"paneKey\":\"first\",\"state\":\"\(firstState)\"},{\"paneKey\":\"second\",\"state\":\"working\"}]}]}}".utf8)
            return try OrcaPoller.decode(status: status, worktrees: bytes)
        }
        for (tick, state) in [(1.0, "working"), (2.0, "done")] {
            for row in try snapshot(state) {
                let resolution = OrcaHostResolver().resolve(status: OrcaStatusPayload(version: "1.4.220"), rows: [row],
                    snapshotMonotonic: tick, receivedMonotonic: tick, nowMonotonic: tick,
                    sequenceBase: sequences[row.sessionID, default: 0])
                for event in resolution.events { _ = try runtime.ingest(JSONEncoder().encode(event), now: tick) }
                sequences[row.sessionID, default: 0] += 1
            }
        }
        #expect(runtime.tasks(now: 2).filter { $0.state == .working }.count == 1)
        #expect(runtime.tasks(now: 2).filter { $0.state == .idle }.count == 1)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAMLID_LIVE_ORCA_PROBE"] == "1"))
    func liveReadOnlyProbe() throws {
        let rows = try OrcaPoller().poll(consent: true)
        #expect(rows.count <= 20)
        #expect(rows.allSatisfy { $0.host == "local" })
    }
    @Test func subprocessTimeoutAndOutputBound() throws {
        let executable = URL(fileURLWithPath: "/bin/sh")
        let started = ContinuousTime.now
        #expect(throws: (any Error).self) { try OrcaPoller.run(executable: executable, arguments: ["-c", "exec sleep 10"], timeout: 0.05) }
        #expect(ContinuousTime.now - started < 1)
        #expect(throws: (any Error).self) { try OrcaPoller.run(executable: executable, arguments: ["-c", "head -c 70000 /dev/zero"]) }
        #expect(try OrcaPoller.run(executable: executable, arguments: ["-c", "printf test"]) == Data("test".utf8))
    }
}
