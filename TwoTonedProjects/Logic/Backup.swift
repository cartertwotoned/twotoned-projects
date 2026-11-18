import Foundation
import SwiftData

/// Full JSON backup of every project, list and item.
enum Backup {
    nonisolated struct File: Codable, Sendable {
        var format = "twotoned-projects-backup"
        var version = 1
        var exportedAt: Date
        var projects: [ProjectRecord]
        var brainstorm: [BrainstormRecord]?
    }

    nonisolated struct ProjectRecord: Codable, Sendable {
        var id: UUID
        var name: String
        var status: String
        var sortIndex: Int
        var colorHex: String?
        var iconData: Data?
        var githubURL: String
        var summary: String
        var createdAt: Date
        var folders: [FolderLink]?
        var lists: [ListRecord]
        var items: [ItemRecord]
    }

    nonisolated struct ListRecord: Codable, Sendable {
        var id: UUID
        var name: String
        var sortIndex: Int
        var includeInUpNext: Bool
        var isBugList: Bool
        var isDefault: Bool
        var symbol: String
    }

    nonisolated struct ItemRecord: Codable, Sendable {
        var id: UUID
        var listID: UUID?
        var title: String
        var notes: String
        var priority: Int
        var dueDate: Date?
        var tags: [String]
        var subtasks: [Subtask]
        var links: [String]
        var attachments: [Attachment]?
        var showsBugDetails: Bool
        var stepsToReproduce: String
        var expectedBehavior: String
        var actualBehavior: String
        var screenshotData: Data?
        var createdAt: Date
        var modifiedAt: Date
        var completedAt: Date?
        var rank: Double
        var createdBy: String
        var lastModifiedBy: String
    }

    nonisolated struct BrainstormRecord: Codable, Sendable {
        var id: UUID
        var text: String
        var points: [BrainstormPoint]
        var sortIndex: Int
        var createdAt: Date
    }

    static func makeFile(from projects: [Project], brainstorm: [BrainstormIdea] = []) -> File {
        var file = makeProjectsFile(from: projects)
        file.brainstorm = brainstorm.map {
            BrainstormRecord(id: $0.id, text: $0.text, points: $0.points, sortIndex: $0.sortIndex, createdAt: $0.createdAt)
        }
        return file
    }

    private static func makeProjectsFile(from projects: [Project]) -> File {
        File(exportedAt: .now, projects: projects.map { p in
            ProjectRecord(
                id: p.id, name: p.name, status: p.statusRaw, sortIndex: p.sortIndex, colorHex: p.colorHex,
                iconData: p.iconData, githubURL: p.githubURL, summary: p.summary, createdAt: p.createdAt,
                folders: p.folders,
                lists: p.sortedLists.map { l in
                    ListRecord(id: l.id, name: l.name, sortIndex: l.sortIndex, includeInUpNext: l.includeInUpNext,
                               isBugList: l.isBugList, isDefault: l.isDefault, symbol: l.symbol)
                },
                items: p.allItems.map { i in
                    ItemRecord(
                        id: i.id, listID: i.list?.id, title: i.title, notes: i.notes, priority: i.priorityRaw,
                        dueDate: i.dueDate, tags: i.tags, subtasks: i.subtasks, links: i.links, attachments: i.attachments,
                        showsBugDetails: i.showsBugDetails, stepsToReproduce: i.stepsToReproduce,
                        expectedBehavior: i.expectedBehavior, actualBehavior: i.actualBehavior,
                        screenshotData: i.screenshotData, createdAt: i.createdAt, modifiedAt: i.modifiedAt,
                        completedAt: i.completedAt, rank: i.rank, createdBy: i.createdByRaw,
                        lastModifiedBy: i.lastModifiedByRaw)
                })
        })
    }

    static func encode(_ projects: [Project], brainstorm: [BrainstormIdea] = []) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(makeFile(from: projects, brainstorm: brainstorm))
    }

    struct ImportSummary {
        var imported = 0
        var skipped = 0
    }

    /// Adds projects from a backup. Projects that already exist (same ID) are skipped,
    /// so importing never overwrites anything.
    static func restore(_ data: Data, into context: ModelContext) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.format == "twotoned-projects-backup" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let existing = Set(((try? context.fetch(FetchDescriptor<Project>())) ?? []).map(\.id))
        var summary = ImportSummary()
        for record in file.projects {
            if existing.contains(record.id) { summary.skipped += 1; continue }
            let project = Project(name: record.name, status: ProjectStatus(rawValue: record.status) ?? .active,
                                  sortIndex: record.sortIndex)
            project.id = record.id
            project.colorHex = record.colorHex
            project.iconData = record.iconData
            project.githubURL = record.githubURL
            project.summary = record.summary
            project.createdAt = record.createdAt
            project.folders = record.folders ?? []
            context.insert(project)

            var listsByID: [UUID: TaskList] = [:]
            for l in record.lists {
                let list = TaskList(name: l.name, sortIndex: l.sortIndex, includeInUpNext: l.includeInUpNext,
                                    isBugList: l.isBugList, isDefault: l.isDefault, symbol: l.symbol)
                list.id = l.id
                context.insert(list)
                list.project = project
                listsByID[l.id] = list
            }
            for r in record.items {
                let item = Item(title: r.title, list: r.listID.flatMap { listsByID[$0] }, project: project)
                item.id = r.id
                item.notes = r.notes
                item.priorityRaw = r.priority
                item.dueDate = r.dueDate
                item.tags = r.tags
                item.subtasks = r.subtasks
                item.links = r.links
                item.attachments = r.attachments ?? []
                item.showsBugDetails = r.showsBugDetails
                item.stepsToReproduce = r.stepsToReproduce
                item.expectedBehavior = r.expectedBehavior
                item.actualBehavior = r.actualBehavior
                item.screenshotData = r.screenshotData
                item.createdAt = r.createdAt
                item.modifiedAt = r.modifiedAt
                item.completedAt = r.completedAt
                item.rank = r.rank
                item.createdByRaw = r.createdBy
                item.lastModifiedByRaw = r.lastModifiedBy
                context.insert(item)
            }
            summary.imported += 1
        }
        let existingIdeas = Set(((try? context.fetch(FetchDescriptor<BrainstormIdea>())) ?? []).map(\.id))
        for record in file.brainstorm ?? [] where !existingIdeas.contains(record.id) {
            let idea = BrainstormIdea(text: record.text, sortIndex: record.sortIndex)
            idea.id = record.id
            idea.points = record.points
            idea.createdAt = record.createdAt
            context.insert(idea)
        }
        return summary
    }
}

/// Human-readable Markdown export of one project.
enum MarkdownExport {
    static func markdown(for project: Project) -> String {
        var out = "# \(project.name)\n\n"
        out += "Status: \(project.status.title)\n"
        if !project.githubURL.isEmpty { out += "GitHub: \(project.githubURL)\n" }
        if !project.summary.isEmpty { out += "\n\(project.summary)\n" }

        let upNext = Ordering.upNext(for: project)
        if !upNext.isEmpty {
            out += "\n## Up Next\n\n"
            for (i, item) in upNext.enumerated() {
                out += "\(i + 1). \(line(for: item, showList: true))\n"
            }
        }
        for list in project.sortedLists {
            let items = Ordering.openItems(in: list)
            out += "\n## \(list.name)\n\n"
            if items.isEmpty { out += "_Empty_\n" }
            for item in items {
                out += "- [ ] \(line(for: item, showList: false))\n"
                if !item.notes.isEmpty {
                    out += item.notes.split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "  \($0)" }.joined(separator: "\n") + "\n"
                }
                for sub in item.subtasks {
                    out += "  - [\(sub.isDone ? "x" : " ")] \(sub.title)\n"
                }
            }
        }
        let done = project.allItems.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        if !done.isEmpty {
            out += "\n## Done\n\n"
            for item in done {
                let date = item.completedAt?.formatted(date: .abbreviated, time: .omitted) ?? ""
                out += "- [x] \(item.title) _(\(item.list?.name ?? "No list"), \(date))_\n"
            }
        }
        return out
    }

    private static func line(for item: Item, showList: Bool) -> String {
        var parts = [item.title]
        var meta: [String] = []
        if showList, let list = item.list { meta.append(list.name) }
        if item.priority != .none { meta.append(item.priority.title) }
        if let due = item.dueDate { meta.append("due \(due.formatted(date: .abbreviated, time: .omitted))") }
        if !item.tags.isEmpty { meta.append(item.tags.map { "#\($0)" }.joined(separator: " ")) }
        if !meta.isEmpty { parts.append("_(\(meta.joined(separator: ", ")))_") }
        return parts.joined(separator: " ")
    }
}
