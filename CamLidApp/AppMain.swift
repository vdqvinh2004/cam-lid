import AppKit
import CamLidCore
import CamLidApp

/// Native preview host; coordinator owns local runtime and UI. Power actuation is disabled.
@main
enum CamLidMain {
    static func main() {
        // Privileged install/uninstall launched by the administrator prompt; runs before any UI exists.
        if let status = HelperAdminCommand.runIfRequested(arguments: ProcessInfo.processInfo.arguments) { exit(status) }
        if let status = HelperAdminCommand.runInspectIfRequested(arguments: ProcessInfo.processInfo.arguments) { exit(status) }
        let coordinator: NSObject & NSApplicationDelegate = ProcessInfo.processInfo.arguments.contains("--utility-ui") ? UtilityUICoordinator() : AppCoordinator()
        NSApplication.shared.delegate = coordinator
        // Retain for process lifetime; NSApplication holds the delegate weakly.
        _ = Unmanaged.passRetained(coordinator)
        NSApplication.shared.run()
    }
}
