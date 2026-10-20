import AppKit
import CamLidCore
import CamLidApp

/// Native preview host; coordinator owns local runtime and UI. Power actuation is disabled.
@main
enum CamLidMain {
    static func main() {
        let coordinator: NSObject & NSApplicationDelegate = ProcessInfo.processInfo.arguments.contains("--utility-ui") ? UtilityUICoordinator() : AppCoordinator()
        NSApplication.shared.delegate = coordinator
        // Retain for process lifetime; NSApplication holds the delegate weakly.
        _ = Unmanaged.passRetained(coordinator)
        NSApplication.shared.run()
    }
}
