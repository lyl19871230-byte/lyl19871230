import SwiftUI
import UIKit
import UserNotifications

@main
struct DailyTaskVoiceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var taskStore = TaskStore()
    @StateObject private var notificationManager = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(taskStore)
                .environmentObject(notificationManager)
                .task {
                    appDelegate.taskStore = taskStore
                    notificationManager.configure(taskStore: taskStore)
                    await notificationManager.requestAuthorization()
                    await notificationManager.registerCategories()
                    await notificationManager.rescheduleAll(tasks: taskStore.tasks, settings: taskStore.settings)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var taskStore: TaskStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == NotificationManager.completeActionIdentifier else { return }
        guard let taskId = response.notification.request.content.userInfo["taskId"] as? String else { return }
        await MainActor.run {
            taskStore?.completeTask(idString: taskId)
        }
    }
}
