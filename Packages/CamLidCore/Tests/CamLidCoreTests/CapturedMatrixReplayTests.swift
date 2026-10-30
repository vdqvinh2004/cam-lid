import Foundation
import Testing
@testable import CamLidCore

// Historical parser regressions, not qualification of the passive product observer.
@Suite("Historical provider replay regressions")
struct CapturedMatrixReplayTests {
    @Test(arguments: ["codex-success.jsonl", "codex-fail.jsonl", "opencode-success.jsonl"])
    func committedFixturesReachRealRuntimeWithoutPrematureCompletion(_ name: String) throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Matrix/\(name)")
        let provider = name.hasPrefix("codex-") ? "codex" : "opencode"
        var stream = try ProviderStream(provider: provider)
        var runtime = RuntimeAgentStore()
        var states: [TaskState] = []
        for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
            for event in try stream.consume(Data(line.utf8), now: 1) {
                states.append(event.state)
                _ = try runtime.ingest(JSONEncoder().encode(event), now: 1)
            }
            if line.contains("\"step_finish\"") {
                #expect(runtime.tasks(now: 1).map(\.state) == [.working])
            }
        }
        #expect(states == (provider == "codex" ? [.working, .idle] : [.working, .working]))
        let lastState = try #require(states.last)
        #expect(runtime.tasks(now: 1).map(\.state) == [lastState])
        for event in try stream.disconnected(now: 2) {
            _ = try runtime.ingest(JSONEncoder().encode(event), now: 2)
        }
        #expect(runtime.tasks(now: 2).map(\.state) == [provider == "codex" ? .idle : .unknown])
    }

    // The private 40-run archive is optional; explicitly requesting it still fails on missing files.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAMLID_CAPTURED_MATRIX_DIRECTORY"] != nil))
    func allFortyArchivedStreamsReachRealRuntimeWithoutPrematureStepCompletion() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["CAMLID_CAPTURED_MATRIX_DIRECTORY"])
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        for provider in ["codex", "opencode"] {
            for number in 1...20 {
                let file = root.appendingPathComponent(String(format: "%@/run-%02d.jsonl", provider, number))
                let contents = try String(contentsOf: file, encoding: .utf8)
                var stream = try ProviderStream(provider: provider)
                var runtime = RuntimeAgentStore()
                for line in contents.split(separator: "\n") {
                    for event in try stream.consume(Data(line.utf8), now: 1) {
                        _ = try runtime.ingest(JSONEncoder().encode(event), now: 1)
                    }
                }
                for event in try stream.disconnected(now: 2) {
                    _ = try runtime.ingest(JSONEncoder().encode(event), now: 2)
                }
                #expect(!runtime.tasks(now: 2).contains { $0.state == .working })
            }
        }
    }
}
