import Foundation
import Testing
@testable import CamLidCore

@Suite("Captured matrix acceptance replays")
struct CapturedMatrixReplayTests {
    @Test func allFortyStreamsReachRealRuntimeWithoutPrematureStepCompletion() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        for provider in ["codex", "opencode"] {
            for number in 1...20 {
                let file = root.appendingPathComponent(String(format: "docs/qa/preview-evidence/provider-matrix/%@/run-%02d.jsonl", provider, number))
                let contents = try String(contentsOf: file, encoding: .utf8)
                var stream = try ProviderStream(provider: provider)
                var runtime = RuntimeAgentStore()
                for line in contents.split(separator: "\n") {
                    for event in try stream.consume(Data(line.utf8), now: 1) {
                        // Exercises actual sequence/tombstone and acceptance seam,
                        // unlike collecting adapter enums without normalization.
                        _ = try runtime.ingest(JSONEncoder().encode(event), now: 1)
                    }
                }
                for event in try stream.disconnected(now: 2) { _ = try runtime.ingest(JSONEncoder().encode(event), now: 2) }
                #expect(!runtime.tasks(now: 2).contains { $0.state == .working })
            }
        }
    }
}
