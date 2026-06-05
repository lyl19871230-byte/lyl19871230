import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let completeActionIdentifier = "TASK_COMPLETE_ACTION"
    static let categoryIdentifier = "DAILY_TASK_CATEGORY"

    @Published private(set) var isAuthorized = false
    private weak var taskStore: TaskStore?

    func configure(taskStore: TaskStore) {
        self.taskStore = taskStore
    }

    func requestAuthorization() async {
        do {
            isAuthorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isAuthorized = false
        }
    }

    func registerCategories() async {
        let complete = UNNotificationAction(
            identifier: Self.completeActionIdentifier,
            title: "完成",
            options: [.authenticationRequired]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [complete],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func schedule(task: TaskItem) async {
        guard !task.isCompleted else { return }

        let content = UNMutableNotificationContent()
        content.title = "今日任务"
        content.body = task.title
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["taskId": task.id.uuidString]

        var date = DateComponents()
        date.hour = task.reminderHour
        date.minute = task.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: task.id),
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    func rescheduleAll(tasks: [TaskItem], settings: AppSettings) async {
        let ids = tasks.map { Self.notificationIdentifier(for: $0.id) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)

        for task in tasks where !task.isCompleted {
            var scheduledTask = task
            scheduledTask.reminderHour = settings.reminderHour
            scheduledTask.reminderMinute = settings.reminderMinute
            await schedule(task: scheduledTask)
        }
    }

    static func cancelNotification(for taskId: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: taskId)])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier(for: taskId)])
    }

    static func notificationIdentifier(for taskId: UUID) -> String {
        "daily-task-\(taskId.uuidString)"
    }
}

