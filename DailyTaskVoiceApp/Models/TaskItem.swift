import Foundation

enum AttachmentKind: String, Codable, Equatable {
    case image
    case audio
    case file
}

struct AttachmentItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: AttachmentKind
    var localPath: String
    var displayName: String
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var rawText: String
    var createdAt: Date = Date()
    var reminderHour: Int
    var reminderMinute: Int
    var isCompleted: Bool = false
    var completedAt: Date?
    var attachments: [AttachmentItem] = []
}

struct AppSettings: Codable, Equatable {
    var reminderHour: Int = 8
    var reminderMinute: Int = 0

    var reminderDate: Date {
        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute
        return Calendar.current.date(from: components) ?? Date()
    }
}

