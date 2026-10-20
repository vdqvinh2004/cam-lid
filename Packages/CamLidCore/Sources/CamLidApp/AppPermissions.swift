import AppKit

// Keep the retired Accessibility case decodable so old utility intent is refused.
enum AppPermission: String, Codable, Sendable {
    case accessibility, notifications

    var settingsURL: URL {
        // shortcut: macOS Settings pane URLs are not stable; fall back to the Settings app.
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    }
}

@MainActor
final class AppPermissions {
    private let supported: Bool
    private let openSettings: (URL) -> Bool
    let accessibility = "notRequired"
    let promptRequested = false
    private(set) var settingsError: String?

    init(supported: Bool = Bundle.main.bundleURL.pathExtension == "app",
         checkAccessibility: @escaping () -> Bool = { false },
         promptAccessibility: @escaping () -> Void = {},
         openSettings: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.supported = supported
        self.openSettings = openSettings
    }

    // Retired entry points are inert, including calls from older utility hosts.
    func refresh() {}
    func requestAtStartup() {}
    func requestAccessibility() {}

    func open(_ permission: AppPermission) {
        guard permission == .notifications else {
            settingsError = "Accessibility observation was removed; CamLid does not need this permission."
            return
        }
        guard supported else { settingsError = "System Settings is unavailable in this host."; return }
        settingsError = nil
        if !openSettings(permission.settingsURL),
           !openSettings(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            settingsError = "Couldn’t open System Settings. Open Notifications from the Apple menu."
        }
    }
}
