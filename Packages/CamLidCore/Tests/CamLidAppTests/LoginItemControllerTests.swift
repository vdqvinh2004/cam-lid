import Foundation
import Testing
import CamLidCLI
import CamLidCore
@testable import CamLidApp

@Suite("M8 login intent") struct LoginItemControllerTests {
    @Test @MainActor func savedLoginIntentNeverResumesAMode() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.launchAtLogin = true; patch.mode = .auto
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Login intent did not save"); return
        }
        let restarted = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: restarted.handleControl(.status, payload: Data()))
        let object = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        #expect(object["configuredMode"] as? String == "auto")
        #expect(object["activeSessionMode"] is NSNull && object["powerActuation"] as? Bool == false)
    }
    @Test @MainActor func noRegistrationDuringStatusReadAndErrorsRemainVisible() {
        var registered = 0; var disabled = 0
        let controller = LoginItemController(status: { "notRegistered" }, register: { registered += 1 }, unregister: { disabled += 1 })
        controller.refresh()
        #expect(controller.state == "notRegistered" && registered == 0 && disabled == 0)
        controller.apply(true)
        #expect(registered == 1 && controller.state == "notRegistered")
        controller.apply(false)
        #expect(disabled == 1)
        let failing = LoginItemController(status: { "requiresApproval" }, register: { throw TestFailure.denied }, unregister: {})
        failing.apply(true)
        #expect(failing.state == "error" && failing.message.contains("Couldn’t"))
        failing.refresh(); #expect(failing.state == "requiresApproval")
    }
}
private enum TestFailure: Error { case denied }
