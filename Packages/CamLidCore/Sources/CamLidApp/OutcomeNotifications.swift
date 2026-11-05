import Foundation
import UserNotifications
import CamLidCore

struct NotificationBudget {
    private var ordinary: [(key: String, time: Double)] = []
    private var criticalSession: String?
    private var criticalReasons: Set<String> = []
    mutating func admit(session: String, event: String, category: NotificationCategory, reason: String, now: Double) -> Bool {
        guard now.isFinite, now >= 0 else { return false }
        ordinary.removeAll { now - $0.time >= 600 || now < $0.time }
        if category == .safety || category == .restoration {
            if criticalSession != session { criticalSession = session; criticalReasons.removeAll() }
            let key = category.rawValue + ":" + reason
            guard criticalReasons.count < 64, criticalReasons.insert(key).inserted else { return false }
            return true
        }
        let key = session + ":" + event + ":" + category.rawValue + ":" + reason
        guard ordinary.count < 5, !ordinary.contains(where: { $0.key == key }) else { return false }
        ordinary.append((key, now)); return true
    }
}
@MainActor final class OutcomeNotifications {
    private var budget = NotificationBudget()
    private var requesting = false
    private(set) var permission = "notDetermined"
    var permissionState: String { requesting ? "requesting" : permission }
    var onPermissionChanged: (() -> Void)?
    private var enabled: [NotificationCategory] = []
    private let supported: Bool
    private let readPermission: @MainActor () async -> String
    private let requestPermission: @MainActor () async throws -> Void
    private let deliver: @MainActor (UNNotificationRequest) async throws -> Void
    init(supported: Bool = Bundle.main.bundleURL.pathExtension == "app",
         readPermission: @escaping @MainActor () async -> String = {
             switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
             case .authorized: "authorized"
             case .denied: "denied"
             case .notDetermined: "notDetermined"
             case .provisional: "provisional"
             @unknown default: "unknown"
             }
         }, requestPermission: @escaping @MainActor () async throws -> Void = {
             _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
         }, deliver: @escaping @MainActor (UNNotificationRequest) async throws -> Void = {
             try await UNUserNotificationCenter.current().add($0)
         }) {
        self.supported = supported; self.readPermission = readPermission
        self.requestPermission = requestPermission; self.deliver = deliver
    }
    func configure(categories: [NotificationCategory]) { enabled = categories }
    func refresh() async {
        guard supported else { permission = "unavailable"; return }
        permission = await readPermission()
        onPermissionChanged?()
    }
    func authorizeFromUserAction() async {
        guard supported, !requesting else { return }
        requesting = true
        defer { requesting = false; onPermissionChanged?() }
        await refresh()
        guard permission == "notDetermined" else { return }
        onPermissionChanged?()
        do { try await requestPermission(); await refresh() }
        catch { permission = "unavailable" }
        onPermissionChanged?()
    }
    func emit(category: NotificationCategory, session: String, event: String, reason: String, now: Double) {
        guard supported, enabled.contains(category) else { return }
        Task { @MainActor in
            await refresh()
            guard enabled.contains(category), ["authorized", "provisional"].contains(permission),
                  budget.admit(session: session, event: event, category: category, reason: reason, now: now) else { return }
            let content = Self.content(category: category)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await deliver(request)
        }
    }
    static func content(category: NotificationCategory) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "CamLid: " + category.title
        // Fixed templates only: no raw reason, argv, process or history payload.
        switch category {
        case .completion: content.body = "Tracked work settled. Check Activity for the sleep outcome."
        case .failure: content.body = "Tracked work reported a failure. Check Activity for details."
        case .safety: content.body = "A safety condition stopped protection. Check Activity for details."
        case .restoration: content.body = "Recovery needs attention. Check Activity before starting another session."
        }
        content.sound = .default
        return content
    }
}
