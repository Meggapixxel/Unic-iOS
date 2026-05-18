import Foundation
import UserNotifications

/// Manages local push-notification scheduling for test-drive deadline reminders.
final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()
    private init() {}

    private static let testDriveDeadlineDays = 7

    // MARK: - Permission

    /// Requests notification authorization from the user if the status is `notDetermined`.
    /// - Returns: `true` if notifications are authorized after the request.
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Returns whether the user has already granted notification authorization.
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule

    /// Cancels all previously scheduled test-drive notifications and reschedules two per active entry:
    /// one the day before the deadline and one on the deadline itself, both firing at 10:00 AM.
    /// - Parameter entries: The current list of active test-drive entries.
    func scheduleTestDriveReminders(for entries: [TestDriveEntry]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Remove old test-drive notifications before rescheduling
        let pending = await center.pendingNotificationRequests()
        let oldIds = pending.map(\.identifier).filter { $0.hasPrefix("td_") }
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        let now = Date()
        for entry in entries {
            let deadline = entry.date.addingTimeInterval(Double(Self.testDriveDeadlineDays) * 86_400)

            let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: deadline) ?? deadline

            // 1 day before
            if dayBefore > now {
                schedule(
                    id: "td_\(entry.id)_before",
                    title: String.notif_testdrive_soon_title,
                    body: String.notif_testdrive_soon_body(entry.salon.displayName),
                    at: dayBefore,
                    center: center
                )
            }

            // On the deadline day
            if deadline > now {
                schedule(
                    id: "td_\(entry.id)_deadline",
                    title: String.notif_testdrive_deadline_title,
                    body: String.notif_testdrive_deadline_body(entry.salon.displayName),
                    at: deadline,
                    center: center
                )
            }
        }
    }

    // MARK: - Private

    private func schedule(
        id: String,
        title: String,
        body: String,
        at date: Date,
        center: UNUserNotificationCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.hour = 10
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }
}
