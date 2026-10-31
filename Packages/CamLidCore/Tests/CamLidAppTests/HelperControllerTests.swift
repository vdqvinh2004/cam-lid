import Foundation
import Testing
@testable import CamLidApp
@testable import CamLidCore

@MainActor private func settle(_ done: () -> Bool) async {
    for _ in 0..<100 where !done() { try? await Task.sleep(nanoseconds: 50_000_000) }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@Suite struct HelperControllerTests {
    @Test func administratorCommandIsFixedAndRefusesUnsafePaths() {
        #expect(HelperController.administratorCommand(executable: "/Applications/CamLid.app/Contents/MacOS/CamLid", operation: "install")
            == "'/Applications/CamLid.app/Contents/MacOS/CamLid' --helper-admin install")
        #expect(HelperController.administratorCommand(executable: "/Applications/CamLid.app/Contents/MacOS/CamLid", operation: "trust") == nil)
        #expect(HelperController.administratorCommand(executable: "/Apps/Cam'Lid/x", operation: "install") == nil)
        #expect(HelperController.administratorCommand(executable: "/Apps/Cam\"Lid/x", operation: "install") == nil)
        #expect(HelperController.administratorCommand(executable: "/Apps/Cam\\Lid/x", operation: "uninstall") == nil)
        #expect(HelperController.administratorCommand(executable: "", operation: "install") == nil)
    }

    @Test func adminEntryIgnoresOrdinaryLaunchesAndRejectsUnknownOperations() {
        #expect(HelperAdminCommand.runIfRequested(arguments: ["CamLid"]) == nil)
        #expect(HelperAdminCommand.runIfRequested(arguments: ["CamLid", "--helper-admin"]) == nil)
        #expect(HelperAdminCommand.runIfRequested(arguments: ["CamLid", "--helper-admin", "trust"]) == 2)
        #expect(HelperAdminCommand.runInspectIfRequested(arguments: ["CamLid"]) == nil)
    }

    @Test @MainActor func statusMapsToPlainStatesAndInstallRefreshesAfterTheAdminRun() async {
        let installed = Flag()
        let controller = HelperController(
            status: { installed.value ? .installed(loaded: true) : .notInstalled },
            runAdmin: { _ in installed.value = true; return HelperOperationResult(accepted: true, reason: "installed", detail: nil) })
        controller.refresh()
        await settle { controller.state == "notInstalled" }
        #expect(controller.state == "notInstalled")
        controller.install()
        #expect(controller.busy)
        await settle { !controller.busy && controller.state == "installed" }
        #expect(!controller.busy && controller.state == "installed")
    }

    @Test @MainActor func aRefusedInstallShowsAPlainReason() async {
        let controller = HelperController(
            status: { .notInstalled },
            runAdmin: { _ in HelperOperationResult(accepted: false, reason: "cancelled", detail: nil) })
        controller.install()
        await settle { !controller.busy }
        #expect(controller.state == "notInstalled" && controller.message == "Cancelled.")
    }

    @Test @MainActor func anEarlierInstallsIdentityFileAloneReadsAsNotInstalled() async {
        let onlyPins = HelperController(status: { .partial(missing: ["helper", "daemonPlist", "recoveryPlist"]) },
                                        runAdmin: { _ in HelperOperationResult(accepted: false, reason: "cancelled", detail: nil) },
                                        keepAwakeApps: { [] })
        onlyPins.refresh()
        await settle { onlyPins.state != "unknown" }
        #expect(onlyPins.state == "notInstalled")
        let broken = HelperController(status: { .partial(missing: ["recoveryPlist"]) },
                                      runAdmin: { _ in HelperOperationResult(accepted: false, reason: "cancelled", detail: nil) },
                                      keepAwakeApps: { [] })
        broken.refresh()
        await settle { broken.state != "unknown" }
        #expect(broken.state == "partial")
    }

    @Test func theInstallersReasonIsReadFromTheAdministratorPromptError() {
        #expect(HelperController.reason(in: "0:120: execution error: helper-admin: labelInUse (1)") == "labelInUse")
        #expect(HelperController.reason(in: "helper-admin: installed\n") == "installed")
        #expect(HelperController.reason(in: "User canceled. (-128)") == nil)
    }

    /// Claude Code (and Orca) run `caffeinate` while they work; only one started outside an agent is "another
    /// keep-awake app".
    @Test func caffeinateStartedByAnAgentIsNotAnotherKeepAwakeApp() throws {
        let table: [Int32: (parent: Int32, name: String)] = [
            100: (90, "caffeinate"), 90: (80, "orca"),                       // Orca's own caffeinate
            200: (190, "caffeinate"), 190: (180, "claude"), 180: (1, "zsh"),
            300: (290, "caffeinate"), 290: (280, "zsh"), 280: (270, "login"), 270: (1, "ghostty"),
            400: (390, "caffeinate"), 390: (380, "a"), 380: (370, "b"), 370: (360, "c"), 360: (350, "d"), 350: (1, "claude")]
        #expect(HelperController.startedByAgent(100) { table[$0] })
        #expect(HelperController.startedByAgent(200) { table[$0] })
        #expect(!HelperController.startedByAgent(300) { table[$0] })
        #expect(!HelperController.startedByAgent(400) { table[$0] })      // beyond four ancestors
        // A real caffeinate started here (not by an agent) is found and counted.
        let plain = Process()
        plain.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate"); plain.arguments = ["-t", "20"]
        try plain.run(); defer { plain.terminate() }
        Thread.sleep(forTimeInterval: 0.3)
        #expect(HelperController.pids(named: "caffeinate").contains(plain.processIdentifier))
    }
}
