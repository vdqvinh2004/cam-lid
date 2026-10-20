import Testing
@testable import CamLidApp

@Suite("Application termination drain gate")
struct ApplicationTerminationTests {
    @Test func terminationRequiresEveryDrainUnlessUserExplicitlyChoosesQuit() {
        #expect(TerminationDrainDecision.shouldTerminate(
            editorSettled: true, settingsInstallSettled: true, historyDrained: true))
        #expect(!TerminationDrainDecision.shouldTerminate(
            editorSettled: false, settingsInstallSettled: true, historyDrained: true))
        #expect(!TerminationDrainDecision.shouldTerminate(
            editorSettled: true, settingsInstallSettled: false, historyDrained: true))
        #expect(!TerminationDrainDecision.shouldTerminate(
            editorSettled: true, settingsInstallSettled: true, historyDrained: false))
    }

    @Test func unconfirmedDrainDefaultsToKeepOpenAndNeedsExplicitQuitChoice() {
        #expect(!TerminationDrainDecision.shouldTerminate(
            editorSettled: true, settingsInstallSettled: false, historyDrained: false))
        #expect(!TerminationDrainDecision.shouldTerminate(
            editorSettled: true, settingsInstallSettled: false, historyDrained: false,
            choice: .keepOpen))
        #expect(TerminationDrainDecision.shouldTerminate(
            editorSettled: true, settingsInstallSettled: false, historyDrained: false,
            choice: .quitWithoutPendingHistory))
    }
}
