import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

/// Spec 018 US2 (ADR 0006): an admitted `camlid run` command is renewed and finished through its own payloads. A
/// regression once decoded these payloads as CLI options first, so every renewal failed and the hold outlived its command.
@Suite("camlid run admission in the app", .serialized)
struct CommandRunAdmissionTests {
    @Test @MainActor func admissionRenewalAndFinishEachAcceptTheirOwnPayload() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        app.changeMode(.auto)
        await app.startPreviewSession()

        let admitPayload = try JSONEncoder().encode(AdmitCommandRequest(label: "test command"))
        let admitReply = try await app.handleControlAsync(
            .admitCommand, payload: admitPayload, deadline: ContinuousTime.now + 2)
        let admitted = try JSONDecoder().decode(CLIResult.self, from: admitReply)
        #expect(admitted.exitCode == 0)
        let receipt = try JSONDecoder().decode(CommandReceipt.self, from: Data(admitted.json.utf8))

        let renewReply = try app.handleControl(
            .renewCommand, payload: try JSONEncoder().encode(RenewCommandRequest(receipt: receipt)))
        let renewed = try JSONDecoder().decode(CLIResult.self, from: renewReply)
        #expect(renewed.exitCode == 0)
        let current = try JSONDecoder().decode(CommandReceipt.self, from: Data(renewed.json.utf8))

        let finishPayload = try JSONEncoder().encode(
            FinishCommandRequest(receipt: current, exitStatus: 0, durationSeconds: 1))
        let finished = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.finishCommand, payload: finishPayload))
        #expect(finished.exitCode == 0)

        // A finished receipt is single-use: renewing it again is refused with its reason, not an unavailable error.
        let stale = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(
            .renewCommand, payload: try JSONEncoder().encode(RenewCommandRequest(receipt: current))))
        #expect(stale.exitCode == 3)
    }
}
