import Foundation
import TokenDeskCore
import UserNotifications

/// Local-notification adapter that never embeds credentials or remote account identifiers.
@MainActor
public final class NotificationService: NotificationServicing {
    private let center: UNUserNotificationCenter

    /// Creates a notification service backed by the app's notification center.
    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Reads authorization without prompting.
    public func authorizationStatus() async -> PermissionAuthorization {
        let settings = await center.notificationSettings()
        return Self.authorization(from: settings.authorizationStatus)
    }

    /// Requests alert, sound, and badge authorization after the user enables notifications.
    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Schedules a generic test notification containing no account data or secrets.
    public func sendTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Token Desk 测试通知"
        content.body = "本地告警已准备就绪。"
        let request = UNNotificationRequest(
            identifier: "settings.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    static func authorization(from status: UNAuthorizationStatus) -> PermissionAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .unavailable
        }
    }
}
