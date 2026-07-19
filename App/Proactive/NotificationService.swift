import Foundation
import UserNotifications

/// Real system notifications for proactive nudges. Requests authorization on the
/// first proactive enable, posts banners (title = nudge title, body = message),
/// and routes banner clicks / dismissals back to the app. Delivery is additive:
/// nudges still land in chat and glow the notch; this puts them on screen too.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    /// Posted alongside the click closure so a notch panel can expand if it observes it.
    static let openNotch = Notification.Name("jarvis.openNotch")

    /// Fired on the main actor when the user clicks a proactive banner.
    var onActivate: (@MainActor () -> Void)?
    /// Fired when the user dismisses a banner (feeds the funnel's dismissal backoff).
    var onDismiss: (@MainActor () -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask once, on first proactive enable. Safe to call repeatedly — the system
    /// only prompts the user the first time.
    func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a banner now. Silently no-ops if the user denied authorization.
    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Jarvis" : title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate
    // These callbacks arrive on a private queue; call the completion handler
    // synchronously and hop only Sendable values to the main actor.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound]) // show even while Jarvis is frontmost
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let dismissed = response.actionIdentifier == UNNotificationDismissActionIdentifier
        completionHandler()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if dismissed {
                self.onDismiss?()
            } else {
                NotificationCenter.default.post(name: Self.openNotch, object: nil)
                self.onActivate?()
            }
        }
    }
}
