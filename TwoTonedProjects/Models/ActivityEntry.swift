import Foundation
import SwiftData

/// One line in a project's Activity log (changes by you or Claude).
@Model
final class ActivityEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var authorRaw: String = Author.user.rawValue
    var summary: String = ""
    var symbol: String = "circle"
    var itemID: UUID?
    var project: Project?

    init(summary: String, author: Author, symbol: String, itemID: UUID?) {
        self.id = UUID()
        self.date = .now
        self.summary = summary
        self.authorRaw = author.rawValue
        self.symbol = symbol
        self.itemID = itemID
    }

    var author: Author { Author(rawValue: authorRaw) ?? .user }
}

enum ActivityLog {
    static let maxEntriesPerProject = 300

    static func record(_ project: Project?, _ author: Author, _ summary: String, symbol: String, item: Item? = nil) {
        guard let project, let context = project.modelContext else { return }
        let entry = ActivityEntry(summary: summary, author: author, symbol: symbol, itemID: item?.id)
        context.insert(entry)
        entry.project = project
        let all = project.activity ?? []
        if all.count > maxEntriesPerProject + 20 {
            for old in all.sorted(by: { $0.date > $1.date }).dropFirst(maxEntriesPerProject) { context.delete(old) }
        }
    }
}
