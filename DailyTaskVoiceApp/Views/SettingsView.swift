import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var apiKey = ""
    @State private var reminderDate = Date()
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("GLM API") {
                    SecureField("请输入 GLM API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存 API Key") {
                        saveAPIKey()
                    }
                }

                Section("每日推送") {
                    DatePicker("推送时间", selection: $reminderDate, displayedComponents: .hourAndMinute)
                    Button("保存推送时间") {
                        saveReminderTime()
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                apiKey = (try? KeychainService.readAPIKey()) ?? ""
                reminderDate = taskStore.settings.reminderDate
            }
        }
    }

    private func saveAPIKey() {
        do {
            try KeychainService.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            message = "API Key 已保存。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveReminderTime() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        let settings = AppSettings(
            reminderHour: components.hour ?? 8,
            reminderMinute: components.minute ?? 0
        )
        taskStore.updateSettings(settings)
        Task {
            await notificationManager.rescheduleAll(tasks: taskStore.tasks, settings: settings)
        }
        message = "推送时间已保存。"
    }
}

