import Foundation
import SwiftData

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case active, paused, released, archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .released: "Released"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .active: "bolt.fill"
        case .paused: "pause.circle"
        case .released: "shippingbox"
        case .archived: "archivebox"
        }
    }
}

// Every property has a default and relationships are optional so the store can be
// moved to iCloud (CloudKit) in a future release without a migration rewrite.
@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var statusRaw: String = ProjectStatus.active.rawValue
    var sortIndex: Int = 0
    var colorHex: String?
    @Attribute(.externalStorage) var iconData: Data?
    var githubURL: String = ""
    var summary: String = ""
    var createdAt: Date = Date()
    /// Linked folders (read-only). The primary one is used for README, icon picking and Claude Code.
    var folders: [FolderLink] = []
    /// Back up automatically when items are completed (off by default).
    var autoBackup: Bool = false
    /// Minimum minutes between automatic backups.
    var autoBackupMinutes: Int = 30
    var lastBackupAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TaskList.project)
    var lists: [TaskList]? = []

    @Relationship(deleteRule: .cascade, inverse: \Item.project)
    var items: [Item]? = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityEntry.project)
    var activity: [ActivityEntry]? = []

    init(name: String, status: ProjectStatus = .active, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.statusRaw = status.rawValue
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    /// Lists in display/rank order.
    var sortedLists: [TaskList] {
        (lists ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var allItems: [Item] { items ?? [] }

    var openItems: [Item] { allItems.filter { !$0.isCompleted } }

    var primaryFolder: FolderLink? { folders.first(where: \.isPrimary) ?? folders.first }

    var defaultList: TaskList? {
        let lists = sortedLists
        return lists.first(where: \.isDefault) ?? lists.first(where: \.includeInUpNext) ?? lists.first
    }
}
