import Foundation
import SwiftData

/// UserDefaults keys for app preferences.
enum Prefs {
    /// Show the menu bar item. Off by default.
    static let menuBarEnabled = "menuBar.enabled"
    /// "task" shows the current task's text next to the icon, "icon" shows just the icon.
    static let menuBarLabelStyle = "menuBar.labelStyle"
    /// The project the menu bar and global shortcuts act on.
    static let quickProjectID = "quickProject.id"

    enum LabelStyle: String, CaseIterable, Identifiable {
        case task, icon
        var id: String { rawValue }
        var title: String { self == .task ? "Current task" : "Icon only" }
    }

    static var labelStyle: LabelStyle {
        LabelStyle(rawValue: UserDefaults.standard.string(forKey: menuBarLabelStyle) ?? "") ?? .task
    }
}

/// Resolves which project the menu bar and global shortcuts act on.
enum QuickProject {
    static func resolve(id: String?, in projects: [Project]) -> Project? {
        if let id, let match = projects.first(where: { $0.id.uuidString == id }) { return match }
        let sorted = projects.sorted { $0.sortIndex < $1.sortIndex }
        return sorted.first { $0.status == .active } ?? sorted.first
    }

    static func current(in context: ModelContext) -> Project? {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        return resolve(id: UserDefaults.standard.string(forKey: Prefs.quickProjectID), in: projects)
    }
}
