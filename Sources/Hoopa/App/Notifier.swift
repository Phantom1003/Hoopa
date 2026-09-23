import AppKit
import UserNotifications

/// Due reminders: system notifications. Clicking one jumps to the bound page (handled by AppDelegate).
enum Notifier {
    private static var asked = false

    static func requestIfNeeded() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, err in
            Log.write("Notification permission \(ok) \(err?.localizedDescription ?? "")")
        }
    }

    /// Reschedule from the current state: cancel when there is no time / done / already due, otherwise schedule again.
    static func schedule(_ t: TodoItem) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [t.id.uuidString])
        guard let due = t.due, !t.isDone, due.notifyAt > Date() else { return }
        requestIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = t.title
        content.body = due.isCountdown ? "Countdown finished" : "Due today"
        if let b = t.binding { content.body += " · Click to return to \(b.shortDescription)" }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(due.notifyAt.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: trigger)) { err in
            if let err { Log.write("Scheduling the notification failed \(err.localizedDescription)") }
        }
    }

    static func cancel(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
}
