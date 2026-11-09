import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI
@testable import CamLidApp

@Suite("QA additive live status contract", .serialized)
struct QAStatusContractTests {
    @Test @MainActor func additiveStatusDecodesAsLegacyHealthAndReportsUnavailableValuesAsNull() throws {
        let root = URL(fileURLWithPath: "/tmp/camlid-contract-" + UUID().uuidString)
        let preferences = MemoryPreferences()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppCoordinator(locations: .test(root: root, history: root), preferences: preferences)
        let result = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let status = try JSONSerialization.jsonObject(with: Data(result.json.utf8)) as! [String: Any]
        #expect(status["schemaVersion"] as? Int == 1 && status["powerActuation"] as? Bool == false)
        let health = try #require(status["health"] as? [String: Any])
        let snapshot = try JSONDecoder().decode(HealthSnapshot.self, from: JSONSerialization.data(withJSONObject: health))
        #expect(snapshot.lidState.rawValue == health["lidState"] as? String)
        #expect(snapshot.capabilityVerified == false)
        let temperature = try #require(health["temperature"] as? [String: Any])
        #expect(temperature["valueCelsius"] is NSNull && temperature["source"] is NSNull)
        let providers = try #require(status["agentDetection"] as? [[String: Any]])
        #expect(providers.count == AgentBadgeState.providers.count && providers.allSatisfy { $0["evidenceAgeSeconds"] is NSNull })
        let config = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.configGet, payload: Data()))
        let values = try JSONSerialization.jsonObject(with: Data(config.json.utf8)) as! [String: Any]
        #expect(values["revision"] as? Int == status["revision"] as? Int)
    }
}
