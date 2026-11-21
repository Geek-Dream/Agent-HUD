import Foundation
import UserNotifications

/// A foreground app normally suppresses banners. Important completions opt into
/// the banner; ordinary completions explicitly use only Notification Center.
@MainActor
final class SessionNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    var onOpenSession: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("AgentHUD notification authorization failed: %@", error.localizedDescription)
            } else if !granted {
                NSLog("AgentHUD notifications are disabled in System Settings")
            }
        }
    }

    func notifyCompletion(sessionID: String, provider: String, title: String, summary: String, isImportant: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider) 已完成"
        content.subtitle = title
        content.body = summary
        content.userInfo = ["sessionID": sessionID]
        if isImportant {
            content.sound = .default
            content.interruptionLevel = .active
        } else {
            content.interruptionLevel = .passive
        }
        let identifier = "completion:\(sessionID):\(UUID().uuidString)"
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error {
                NSLog("AgentHUD completion notification failed: %@", error.localizedDescription)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(SessionNotificationPresentation.options(isImportant: notification.request.content.interruptionLevel == .active))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let sessionID = response.notification.request.content.userInfo["sessionID"] as? String {
            Task { @MainActor [weak self] in
                self?.onOpenSession?(sessionID)
            }
        }
        completionHandler()
    }
}
