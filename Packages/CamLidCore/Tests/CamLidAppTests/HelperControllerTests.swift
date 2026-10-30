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
}
