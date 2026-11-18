import Foundation
import SwiftData

/// The tools Claude Code gets, and how they map onto the same actions the UI uses.
///
/// Every call is scoped to one project: the one whose linked folder contains the
/// folder the Claude Code session runs in. Nothing else is reachable.
@MainActor
final class ClaudeTools {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    struct ToolError: Error { let message: String }

    // MARK: Socket entry point

    /// Handles one request from the helper: `{"cwd": "...", "message": <JSON-RPC request>}`.
    func handle(_ data: Data) -> Data {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cwd = envelope["cwd"] as? String,
              let message = envelope["message"] as? [String: Any],
              let method = message["method"] as? String
        else { return encode(["error": ["code": -32600, "message": "Invalid request"]]) }

        switch method {
        case "tools/list":
            return encode(["result": ["tools": Self.definitions]])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try call(name, args: args, cwd: cwd)
                try? context.save()
                return encode(["result": ["content": [["type": "text", "text": text]], "isError": false]])
            } catch let error as ToolError {
                return encode(["result": ["content": [["type": "text", "text": error.message]], "isError": true]])
            } catch {
                return encode(["result": ["content": [["type": "text", "text": "\(error)"]], "isError": true]])
            }
        default:
            return encode(["error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    // MARK: Project scoping

    /// The project whose linked folder contains `cwd` (deepest match wins).
    func project(for cwd: String) -> Project? {
        let target = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().standardizedFileURL.path
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var best: (Project, Int)?
        for project in projects {
            for folder in project.folders {
                let root = folder.url.resolvingSymlinksInPath().standardizedFileURL.path
                if target == root || target.hasPrefix(root.hasSuffix("/") ? root : root + "/") {
                    if root.count > (best?.1 ?? -1) { best = (project, root.count) }
                }
            }
        }
        return best?.0
    }

    private func call(_ name: String, args: [String: Any], cwd: String) throws -> String {
        guard let project = project(for: cwd) else {
            throw ToolError(message: """
                No TwoToned project is linked to this folder (\(cwd)). Tell the user they can link it in \
                TwoToned Projects › Project settings › Folders, then try again.
                """)
        }
        switch name {
        case "get_project": return json(projectSummary(project))
        case "list_items": return try listItems(project, args)
        case "get_item": return json(itemDetail(try item(args, in: project), in: project))
        case "add_item": return try addItem(project, args)
        case "update_item": return try updateItem(project, args)
        case "move_item": return try moveItem(project, args)
        case "complete_item":
            let item = try item(args, in: project)
            if let note = args["note"] as? String, !note.isEmpty { appendNote(note, to: item) }
            ProjectActions.complete(item, by: .claude)
            let next = Ordering.currentTask(for: project)
            return "Completed \"\(item.title)\".\(next.map { " Up Next is now: \"\($0.title)\" (\(shortID($0)))." } ?? " Up Next is empty.")"
        case "reopen_item":
            let item = try item(args, in: project)
            ProjectActions.reopen(item, by: .claude)
            return "Reopened \"\(item.title)\"."
        case "delete_item":
            let item = try item(args, in: project)
            let title = item.title
            ProjectActions.delete(item, context: context, by: .claude)
            return "Deleted \"\(title)\"."
        case "manage_lists": return try manageLists(project, args)
        default: throw ToolError(message: "Unknown tool \(name).")
        }
    }

    // MARK: Tools

    private func listItems(_ project: Project, _ args: [String: Any]) throws -> String {
        let which = (args["list"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "up_next"
        let details = args["include_details"] as? Bool ?? false
        let limit = args["limit"] as? Int ?? 50
        let items: [Item]
        let title: String
        switch which.lowercased() {
        case "", "up_next", "up next", "upnext":
            items = Ordering.upNext(for: project); title = "Up Next"
        case "done", "completed":
            items = project.allItems.filter(\.isCompleted)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            title = "Done"
        case "all", "open":
            items = Ordering.byRank(project.openItems); title = "All open items"
        default:
            let list = try self.list(named: which, in: project)
            items = Ordering.openItems(in: list); title = list.name
        }
        let shown = items.prefix(max(1, limit)).map { details ? itemDetail($0, in: project) : itemSummary($0, in: project) }
        return json(["list": title, "count": items.count, "items": Array(shown)])
    }

    private func addItem(_ project: Project, _ args: [String: Any]) throws -> String {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw ToolError(message: "add_item needs a title.")
        }
        let list: TaskList
        if let name = args["list"] as? String, !name.isEmpty {
            list = try self.list(named: name, in: project)
        } else if let fallback = project.defaultList {
            list = fallback
        } else {
            throw ToolError(message: "This project has no lists. Create one with manage_lists first.")
        }
        let priority = try parsePriority(args["priority"])
        let item = ProjectActions.addItem(QuickAddParser.Result(title: title, listPrefix: nil, priority: priority),
                                          to: list, in: project, context: context, by: .claude)
        try applyFields(args, to: item)
        switch (args["position"] as? String)?.lowercased() {
        case "top": Ordering.makeCurrent(item, in: project)
        case "bottom": Ordering.moveTo(item, position: Int.max, in: project)
        default: break
        }
        return "Added \"\(item.title)\" to \(list.name) as \(shortID(item)).\n" + json(itemSummary(item, in: project))
    }

    private func updateItem(_ project: Project, _ args: [String: Any]) throws -> String {
        let item = try item(args, in: project)
        if let title = args["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty { item.title = title }
        if args["priority"] != nil { item.priority = try parsePriority(args["priority"]) ?? .none }
        try applyFields(args, to: item)
        if let note = args["append_notes"] as? String, !note.isEmpty { appendNote(note, to: item) }
        if let done = args["complete_subtasks"] as? [String] {
            for key in done {
                if let index = item.subtasks.firstIndex(where: { $0.title.caseInsensitiveCompare(key) == .orderedSame })
                    ?? Int(key).flatMap({ $0 >= 1 && $0 <= item.subtasks.count ? $0 - 1 : nil }) {
                    item.subtasks[index].isDone = true
                }
            }
        }
        item.touch(by: .claude)
        ActivityLog.record(project, .claude, "Updated \u{201C}\(item.title)\u{201D}", symbol: "pencil", item: item)
        return "Updated \"\(item.title)\".\n" + json(itemDetail(item, in: project))
    }

    private func moveItem(_ project: Project, _ args: [String: Any]) throws -> String {
        let item = try item(args, in: project)
        var notes: [String] = []
        if let name = args["list"] as? String, !name.isEmpty {
            let list = try self.list(named: name, in: project)
            ProjectActions.move(item, to: list, by: .claude)
            notes.append("moved to \(list.name)")
        }
        if let position = args["position"] {
            let text = "\(position)".lowercased()
            if text == "top" {
                Ordering.makeCurrent(item, in: project)
                notes.append("now the current task")
            } else if text == "bottom" {
                Ordering.moveTo(item, position: Int.max, in: project)
                notes.append("moved to the bottom")
            } else if let n = Int(text), n >= 1 {
                Ordering.moveTo(item, position: n - 1, in: project)
                notes.append("moved to position \(n)")
            } else {
                throw ToolError(message: "position must be \"top\", \"bottom\", or a number like \"3\".")
            }
            item.touch(by: .claude)
            ActivityLog.record(project, .claude, "Reordered \u{201C}\(item.title)\u{201D}", symbol: "arrow.up.arrow.down", item: item)
        }
        guard !notes.isEmpty else { throw ToolError(message: "move_item needs a list, a position, or both.") }
        return "\"\(item.title)\" \(notes.joined(separator: " and ")).\n" + upNextText(project)
    }

    private func manageLists(_ project: Project, _ args: [String: Any]) throws -> String {
        let action = (args["action"] as? String ?? "").lowercased()
        let name = args["name"] as? String ?? ""
        switch action {
        case "create":
            guard !name.isEmpty else { throw ToolError(message: "create needs a name.") }
            let list = ProjectActions.addList(named: name, to: project, context: context)
            if let include = args["include_in_up_next"] as? Bool { list.includeInUpNext = include }
            ActivityLog.record(project, .claude, "Created the \(name) list", symbol: "plus.rectangle.on.rectangle")
        case "rename":
            let list = try self.list(named: name, in: project)
            guard let newName = args["new_name"] as? String, !newName.isEmpty else {
                throw ToolError(message: "rename needs new_name.")
            }
            ActivityLog.record(project, .claude, "Renamed \(list.name) to \(newName)", symbol: "pencil")
            list.name = newName
        case "set_up_next":
            let list = try self.list(named: name, in: project)
            guard let include = args["include_in_up_next"] as? Bool else {
                throw ToolError(message: "set_up_next needs include_in_up_next.")
            }
            list.includeInUpNext = include
        case "reorder":
            guard let order = args["order"] as? [String], !order.isEmpty else {
                throw ToolError(message: "reorder needs order: an array of list names.")
            }
            var lists = try order.map { try self.list(named: $0, in: project) }
            lists += project.sortedLists.filter { list in !lists.contains { $0 === list } }
            for (index, list) in lists.enumerated() { list.sortIndex = index }
        case "delete":
            let list = try self.list(named: name, in: project)
            guard (list.items ?? []).isEmpty else {
                throw ToolError(message: "\(list.name) still has items. Move or delete them first.")
            }
            guard (project.lists?.count ?? 0) > 1 else { throw ToolError(message: "A project needs at least one list.") }
            ActivityLog.record(project, .claude, "Deleted the \(list.name) list", symbol: "trash")
            context.delete(list)
        default:
            throw ToolError(message: "action must be create, rename, set_up_next, reorder, or delete.")
        }
        return json(projectSummary(project))
    }

    // MARK: Helpers

    private func item(_ args: [String: Any], in project: Project) throws -> Item {
        guard let id = (args["id"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces), !id.isEmpty else {
            throw ToolError(message: "Pass the item's id (from list_items).")
        }
        let matches = project.allItems.filter { $0.id.uuidString.lowercased().hasPrefix(id) }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw ToolError(message: "No item with id \(id) in this project.") }
        throw ToolError(message: "More than one item starts with \(id). Use more characters of the id.")
    }

    private func list(named name: String, in project: Project) throws -> TaskList {
        let lists = project.sortedLists
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = lists.first(where: { $0.name.lowercased() == key }) { return exact }
        let prefixed = lists.filter { $0.name.lowercased().hasPrefix(key) }
        if prefixed.count == 1 { return prefixed[0] }
        let names = lists.map(\.name).joined(separator: ", ")
        throw ToolError(message: "No list called \"\(name)\". Lists: \(names).")
    }

    private func parsePriority(_ value: Any?) throws -> Priority? {
        guard let text = (value as? String)?.lowercased(), !text.isEmpty else { return nil }
        if let p = Priority.allCases.first(where: { $0.title.lowercased() == text }) { return p }
        throw ToolError(message: "priority must be none, low, medium, high, or urgent.")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func applyFields(_ args: [String: Any], to item: Item) throws {
        if let notes = args["notes"] as? String { item.notes = notes }
        if let due = args["due_date"] as? String {
            if due.isEmpty {
                item.dueDate = nil
            } else if let date = Self.dayFormatter.date(from: due) {
                item.dueDate = date
            } else {
                throw ToolError(message: "due_date must look like 2026-12-31 (or \"\" to clear it).")
            }
        }
        if let tags = args["tags"] as? [String] { item.tags = tags.map { $0.replacingOccurrences(of: "#", with: "") } }
        if let tags = args["add_tags"] as? [String] {
            for tag in tags.map({ $0.replacingOccurrences(of: "#", with: "") }) where !item.tags.contains(tag) {
                item.tags.append(tag)
            }
        }
        if let subs = args["subtasks"] as? [String] { item.subtasks = subs.map { Subtask(title: $0) } }
        if let subs = args["add_subtasks"] as? [String] { item.subtasks += subs.map { Subtask(title: $0) } }
        if let links = args["links"] as? [String] { item.links = links }
        let bugFields: [(String, ReferenceWritableKeyPath<Item, String>)] = [
            ("steps_to_reproduce", \.stepsToReproduce),
            ("expected_behavior", \.expectedBehavior),
            ("actual_behavior", \.actualBehavior),
        ]
        for (key, path) in bugFields {
            if let value = args[key] as? String {
                item[keyPath: path] = value
                item.showsBugDetails = true
            }
        }
    }

    private func appendNote(_ note: String, to item: Item) {
        item.notes = item.notes.isEmpty ? note : item.notes + "\n\n" + note
    }

    private func shortID(_ item: Item) -> String {
        String(item.id.uuidString.lowercased().prefix(8))
    }

    private func upNextText(_ project: Project) -> String {
        let items = Ordering.upNext(for: project).prefix(10).enumerated().map { index, item in
            "\(index + 1). \(item.title) (\(shortID(item)))"
        }
        return "Up Next:\n" + (items.isEmpty ? "(empty)" : items.joined(separator: "\n"))
    }

    private func projectSummary(_ project: Project) -> [String: Any] {
        let upNext = Ordering.upNext(for: project)
        var summary: [String: Any] = [
            "name": project.name,
            "status": project.status.title,
            "lists": project.sortedLists.map { list in
                ["name": list.name, "open_items": list.openItems.count, "in_up_next": list.includeInUpNext,
                 "is_bug_list": list.isBugList] as [String: Any]
            },
            "up_next": upNext.prefix(10).map { itemSummary($0, in: project) },
            "up_next_count": upNext.count,
        ]
        if let current = upNext.first { summary["current_task"] = itemDetail(current, in: project) }
        if !project.summary.isEmpty { summary["description"] = project.summary }
        if !project.githubURL.isEmpty { summary["github"] = project.githubURL }
        summary["folders"] = project.folders.map(\.path)
        return summary
    }

    private func itemSummary(_ item: Item, in project: Project) -> [String: Any] {
        var out: [String: Any] = ["id": shortID(item), "title": item.title, "list": item.list?.name ?? ""]
        if item.priority != .none { out["priority"] = item.priority.title.lowercased() }
        if let due = item.dueDate { out["due_date"] = Self.dayFormatter.string(from: due) }
        if !item.tags.isEmpty { out["tags"] = item.tags }
        if !item.subtasks.isEmpty {
            out["subtasks_done"] = "\(item.subtasks.filter(\.isDone).count)/\(item.subtasks.count)"
        }
        if item.isCompleted {
            out["status"] = "done"
            if let date = item.completedAt { out["completed"] = date.formatted(.iso8601) }
        } else if let index = Ordering.upNext(for: project).firstIndex(where: { $0 === item }) {
            out["up_next_position"] = index + 1
        }
        if !item.notes.isEmpty { out["has_notes"] = true }
        return out
    }

    private func itemDetail(_ item: Item, in project: Project) -> [String: Any] {
        var out = itemSummary(item, in: project)
        out.removeValue(forKey: "has_notes")
        if !item.notes.isEmpty { out["notes"] = item.notes }
        if !item.subtasks.isEmpty {
            out["subtasks"] = item.subtasks.map { ["title": $0.title, "done": $0.isDone] as [String: Any] }
        }
        if !item.links.isEmpty { out["links"] = item.links }
        if !item.attachments.isEmpty { out["attachments"] = item.attachments.map { $0.url.path } }
        if item.showsBugDetails {
            var bug: [String: String] = [:]
            if !item.stepsToReproduce.isEmpty { bug["steps_to_reproduce"] = item.stepsToReproduce }
            if !item.expectedBehavior.isEmpty { bug["expected_behavior"] = item.expectedBehavior }
            if !item.actualBehavior.isEmpty { bug["actual_behavior"] = item.actualBehavior }
            if item.screenshotData != nil { bug["screenshot"] = "attached in the app" }
            if !bug.isEmpty { out["bug_details"] = bug }
        }
        out["created_by"] = item.createdBy == .claude ? "claude" : "user"
        return out
    }

    private func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
