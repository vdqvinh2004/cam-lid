import Foundation
import ServiceManagement

/// Intent is persisted elsewhere. This controller always reports actual OS state.
@MainActor public final class LoginItemController {
    public private(set) var state = "notRegistered"
    public private(set) var message = ""
    private let readStatus: () -> String
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    public init(status: (() -> String)? = nil, register: (() throws -> Void)? = nil,
                unregister: (() throws -> Void)? = nil) {
        readStatus = status ?? {
            guard Bundle.main.bundleURL.pathExtension == "app" else { return "notFound" }
            switch SMAppService.mainApp.status {
            case .enabled: return "enabled"
            case .requiresApproval: return "requiresApproval"
            case .notRegistered: return "notRegistered"
            case .notFound: return "notFound"
            @unknown default: return "error"
            }
        }
        self.register = register ?? {
            guard Bundle.main.bundleURL.pathExtension == "app" else { throw IPCServiceError.unbundled }
            try SMAppService.mainApp.register()
        }
        self.unregister = unregister ?? {
            guard Bundle.main.bundleURL.pathExtension == "app" else { throw IPCServiceError.unbundled }
            try SMAppService.mainApp.unregister()
        }
    }
    public func refresh() {
        state = readStatus()
        switch state {
        case "enabled": message = "Enabled in macOS. Login opens the app without starting a session."
        case "requiresApproval": message = "Approval required in System Settings → General → Login Items."
        case "notRegistered": message = "Off in macOS."
        case "notFound": message = "macOS can’t find this app for login startup. Install a signed build and retry."
        default: message = "Login registration could not be read."
        }
    }
    public func apply(_ enabled: Bool) {
        do { if enabled { try register() } else { try unregister() }; refresh() }
        catch { state = "error"; message = "Couldn’t update login startup. Check Login Items in System Settings and retry." }
    }
}
private enum IPCServiceError: Error { case unbundled }
