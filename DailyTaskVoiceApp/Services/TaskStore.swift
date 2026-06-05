import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var settings: AppSettings = AppSettings()

    private let tasksURL: URL
    private let settingsURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        tasksURL = documents.appendingPathComponent("tasks.json")
        settingsURL = documents.appendingPathComponent("settings.json")
        load()
    }

    func addTask(title: String, rawText: String, attachments: [AttachmentItem]) -> TaskItem {
        let item = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
            reminderHour: settings.reminderHour,
            reminderMinute: settings.reminderMinute,
            attachments: attachments
        )
        tasks.insert(item, at: 0)
        saveTasks()
        return item
    }

    func updateTask(_ item: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[index] = item
        saveTasks()
    }

    func completeTask(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted = true
        tasks[index].completedAt = Date()
        saveTasks()
        Task {
            await NotificationManager.cancelNotification(for: id)
        }
    }

    func completeTask(idString: String) {
        guard let id = UUID(uuidString: idString) else { return }
        completeTask(id: id)
    }

    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        saveTasks()
        Task {
            await NotificationManager.cancelNotification(for: id)
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        saveSettings()
        for index in tasks.indices where !tasks[index].isCompleted {
            tasks[index].reminderHour = newSettings.reminderHour
            tasks[index].reminderMinute = newSettings.reminderMinute
        }
        saveTasks()
    }

    private func load() {
        if let data = try? Data(contentsOf: tasksURL),
           let decoded = try? JSONDecoder.taskDecoder.decode([TaskItem].self, from: data) {
            tasks = decoded.sorted { $0.createdAt > $1.createdAt }
        }

        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder.taskDecoder.decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }

    private func saveTasks() {
        do {
            let data = try JSONEncoder.taskEncoder.encode(tasks)
            try data.write(to: tasksURL, options: .atomic)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }

    private func saveSettings() {
        do {
            let data = try JSONEncoder.taskEncoder.encode(settings)
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}

private extension JSONEncoder {
    static var taskEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var taskDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

