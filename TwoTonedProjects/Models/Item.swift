import Foundation
import SwiftData

enum Priority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case none = 0, low, medium, high, urgent

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    var symbol: String? {
        switch self {
        case .none: nil
        case .low: "chevron.down"
        case .medium: "equal"
        case .high: "chevron.up"
        case .urgent: "exclamationmark.2"
        }
    }

    static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

enum Author: String, Codable {
    case user, claude
}

nonisolated struct Subtask: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

@Model
final class Item {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var priorityRaw: Int = 0
    var dueDate: Date?
    var tags: [String] = []
    var subtasks: [Subtask] = []
    var links: [String] = []
    var attachments: [Attachment] = []

    // Optional bug detail fields
    var showsBugDetails: Bool = false
    var stepsToReproduce: String = ""
    var expectedBehavior: String = ""
    var actualBehavior: String = ""
    @Attribute(.externalStorage) var screenshotData: Data?

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var completedAt: Date?

    /// Manual position. Every ordered view sorts by this; see `Ordering`.
    var rank: Double = 0

    var createdByRaw: String = Author.user.rawValue
    var lastModifiedByRaw: String = Author.user.rawValue

    var project: Project?
    var list: TaskList?

    init(title: String, list: TaskList?, project: Project?, by author: Author = .user) {
        self.id = UUID()
        self.title = title
        self.list = list
        self.project = project
        self.createdAt = .now
        self.modifiedAt = .now
        self.createdByRaw = author.rawValue
        self.lastModifiedByRaw = author.rawValue
        self.showsBugDetails = list?.isBugList ?? false
    }

    var isCompleted: Bool { completedAt != nil }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var createdBy: Author { Author(rawValue: createdByRaw) ?? .user }
    var lastModifiedBy: Author { Author(rawValue: lastModifiedByRaw) ?? .user }
    var touchedByClaude: Bool { createdBy == .claude || lastModifiedBy == .claude }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    func touch(by author: Author = .user) {
        modifiedAt = .now
        lastModifiedByRaw = author.rawValue
    }
}
