import Foundation
import UserNotifications

struct SessionNotificationSettings: Equatable {
    var importantEnabled = false
    var ordinaryEnabled = false

    func shouldNotify(isImportant: Bool) -> Bool {
        isImportant ? importantEnabled : ordinaryEnabled
    }
}

enum SessionNotificationPresentation {
    static func options(isImportant: Bool) -> UNNotificationPresentationOptions {
        isImportant ? [.banner, .sound, .list] : [.list]
    }

    static func interruptionLevel(isImportant: Bool) -> UNNotificationInterruptionLevel {
        isImportant ? .active : .passive
    }
}
