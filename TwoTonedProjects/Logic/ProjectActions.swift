import Foundation
import SwiftData

/// All mutations go through here so the app UI (and, later, the Claude Code helper)
/// behave identically.
enum ProjectActions {
    @discardableResult
    static func createProject(named name: String, status: ProjectStatus, in context: ModelContext) -> Project {
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let project = Project(name: name, status: status, sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(project)
        let defaults = [
            TaskList(name: "Bugs", sortIndex: 0, isBugList: true, symbol: "ladybug"),
            TaskList(name: "Tasks", sortIndex: 1, isDefault: true, symbol: "checklist"),
            TaskList(name: "Ideas", sortIndex: 2, includeInUpNext: false, symbol: "lightbulb"),
        ]
        for list in defaults {
            context.insert(list)
            list.project = project
        }
        return project
    }

    @discardableResult
    static func addItem(_ draft: QuickAddParser.Result, to list: TaskList, in project: Project,
                        context: ModelContext, by author: Author = .user) -> Item {
        let item = Item(title: draft.title, list: list, project: project, by: author)
        item.priority = draft.priority ?? .none
        context.insert(item)
        Ordering.place(item, in: project)
        ActivityLog.record(project, author, "Added \u{201C}\(item.title)\u{201D} to \(list.name)", symbol: "plus.circle", item: item)
        return item
    }

    static func complete(_ item: Item, by author: Author = .user) {
        guard !item.isCompleted else { return }
        item.completedAt = .now
        item.touch(by: author)
        ActivityLog.record(item.project, author, "Completed \u{201C}\(item.title)\u{201D}", symbol: "checkmark.circle", item: item)
        if let project = item.project { BackupService.shared.itemCompleted(in: project) }
    }

    static func reopen(_ item: Item, by author: Author = .user) {
        guard item.isCompleted, let project = item.project else { return }
        item.completedAt = nil
        item.touch(by: author)
        Ordering.place(item, in: project)
        ActivityLog.record(project, author, "Reopened \u{201C}\(item.title)\u{201D}", symbol: "arrow.uturn.backward.circle", item: item)
    }

    static func toggleComplete(_ item: Item) {
        item.isCompleted ? reopen(item) : complete(item)
    }

    static func move(_ item: Item, to list: TaskList, by author: Author = .user) {
        guard item.list !== list, let project = item.project else { return }
        let wasInUpNext = item.list?.includeInUpNext ?? false
        item.list = list
        if list.isBugList { item.showsBugDetails = true }
        item.touch(by: author)
        // Entering a different ordered set (e.g. Ideas → Tasks): slot it in by the rule.
        if wasInUpNext != list.includeInUpNext, !item.isCompleted {
            Ordering.place(item, in: project)
        }
        ActivityLog.record(project, author, "Moved \u{201C}\(item.title)\u{201D} to \(list.name)", symbol: "arrow.right.circle", item: item)
    }

    static func delete(_ item: Item, context: ModelContext, by author: Author = .user) {
        ActivityLog.record(item.project, author, "Deleted \u{201C}\(item.title)\u{201D}", symbol: "trash")
        context.delete(item)
    }

    static func deleteProject(_ project: Project, context: ModelContext) {
        context.delete(project)
    }

    @discardableResult
    static func addList(named name: String, to project: Project, context: ModelContext) -> TaskList {
        let list = TaskList(name: name, sortIndex: (project.sortedLists.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(list)
        list.project = project
        return list
    }

    static func setDefault(_ list: TaskList, in project: Project) {
        for other in project.lists ?? [] { other.isDefault = (other === list) }
    }
}

/// Parses quick-add text such as `b: crash on launch !high`.
///
/// - A leading `word:` picks the list whose name starts with that word (`b:`, `bug:`, `ideas:`).
/// - `!low`, `!med`, `!medium`, `!high`, `!urgent` set the priority.
enum QuickAddParser {
    struct Result: Equatable {
        var title: String
        var listPrefix: String?
        var priority: Priority?
    }

    /// Parses text against a project: a `word:` prefix only counts if it matches a list,
    /// so a title like "Fix: header" stays intact.
    static func resolve(_ text: String, in project: Project) -> (result: Result, list: TaskList?) {
        let parsed = parse(text)
        if let list = list(for: parsed.listPrefix, in: project) { return (parsed, list) }
        return (parse(text, allowPrefix: false), nil)
    }

    static func parse(_ text: String, allowPrefix: Bool = true) -> Result {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var prefix: String?
        if allowPrefix, let colon = working.firstIndex(of: ":") {
            let head = working[..<colon]
            if !head.isEmpty, head.count <= 12, head.allSatisfy({ $0.isLetter }) {
                prefix = head.lowercased()
                working = String(working[working.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        var priority: Priority?
        let map: [String: Priority] = ["!low": .low, "!med": .medium, "!medium": .medium,
                                       "!high": .high, "!urgent": .urgent]
        let words = working.split(separator: " ", omittingEmptySubsequences: false).filter { word in
            if let p = map[word.lowercased()] { priority = p; return false }
            return true
        }
        working = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return Result(title: working, listPrefix: prefix, priority: priority)
    }

    /// The list a prefix refers to, if any.
    static func list(for prefix: String?, in project: Project) -> TaskList? {
        guard let prefix, !prefix.isEmpty else { return nil }
        return project.sortedLists.first { $0.name.lowercased().hasPrefix(prefix) }
    }
}
