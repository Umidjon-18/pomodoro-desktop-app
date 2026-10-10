import AppKit
import UserNotifications

/// Thin wrapper around user notifications and the completion sound.
/// Every call is safe when notification permission was denied.
@MainActor
enum Notifier {
    private static let presenter = ForegroundPresenter()

    /// Installs the delegate that shows banners while Pomodoro is active. Call once at launch.
    static func configure() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func requestAuthorizationAsync() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Posts "Focus session complete". The sound is played separately (see `playCompletionSound`).
    static func sessionCompleted(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Focus session complete")
        content.body = String(localized: "You focused for \(minutes) min. Take a break.")
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // Fails silently (error ignored) when permission was denied.
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func playCompletionSound() {
        NSSound(named: "Glass")?.play()
    }
}

/// Shows banners even while Pomodoro is the active app (e.g. its menu is open).
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
