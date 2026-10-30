import Testing
import Foundation
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Preview protection readiness", .serialized)
struct ProtectionReadinessTests {
    @Test @MainActor func intentAndModesNeverClaimOrActuateProtection() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var revision = 1
        for mode in RequestedMode.allCases {
            var patch = ConfigPatch(); patch.mode = mode; patch.closedLidOptIn = true
            guard case .saved(let next) = app.applySettingsPatch(patch, expectedRevision: revision) else {
                Issue.record("Expected preference write"); return
            }
            revision = next
            let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
            let status = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
            #expect(status["powerActuation"] as? Bool == false)
            #expect(status["backendVerified"] as? Bool == false && status["leaseVerified"] as? Bool == false)
            let protection = try #require(status["protection"] as? [String: Any])
            #expect(protection["effectiveState"] as? String == "Preview")
            #expect(protection["requestedClosedLidIntent"] as? Bool == true)
            #expect(protection["supportRowID"] is NSNull)
            app.menuBarStartProtection()
            let start = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.start, payload: Data()))
            #expect(start.exitCode == 3 && start.json.contains("backendPendingM1"))
        }
    }
    @Test @MainActor func realStatusHasTypedNullTemperatureAndIndependentPressure() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(healthReader: nil)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let status = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        let health = try #require(status["health"] as? [String: Any])
        let temperature = try #require(health["temperature"] as? [String: Any])
        #expect(temperature["valueCelsius"] is NSNull && temperature["displayName"] is NSNull)
        #expect(temperature["availability"] as? String == "unsupported")
        #expect(health["thermalPressure"] is String)
        #expect((health["lid"] as? [String: Any])?["source"] as? String == "IOPMrootDomain.AppleClamshellState")
        #expect((status["agentDetection"] as? [[String: Any]])?.count == AgentBadgeState.providers.count)
    }
}
