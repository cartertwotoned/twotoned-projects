import SwiftUI
import SwiftData

/// Cross-project overview: each active project's current task, things due soon,
/// and high-priority bugs.
struct WhatsNextView: View {
    let projects: [Project]
    @Environment(Navigator.self) private var nav

    private var active: [Project] { projects.filter { $0.status == .active } }

    private var current: [(Project, Item)] {
        active.compactMap { project in Ordering.currentTask(for: project).map { (project, $0) } }
    }

    private var dueSoon: [Item] {
        let horizon = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!
        let currentIDs = Set(current.map(\.1.id))
        return active.flatMap(\.openItems)
            .filter { item in
                guard let due = item.dueDate else { return false }
                return due < horizon && !currentIDs.contains(item.id)
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var urgentBugs: [Item] {
        let shown = Set(current.map(\.1.id)).union(dueSoon.map(\.id))
        return active.flatMap(\.openItems)
            .filter { ($0.list?.isBugList ?? false) && $0.priority >= .high && !shown.contains($0.id) }
            .sorted(by: Ordering.ruleLess)
    }

    var body: some View {
        let current = current, dueSoon = dueSoon, urgentBugs = urgentBugs
        Group {
            if active.isEmpty {
                ContentUnavailableView("No active projects", systemImage: "bolt.slash",
                                       description: Text("Set a project's status to Active to see it here."))
            } else if current.isEmpty && dueSoon.isEmpty && urgentBugs.isEmpty {
                ContentUnavailableView("Nothing's next", systemImage: "checkmark.seal",
                                       description: Text("Every active project is caught up."))
            } else {
                List {
                    if !current.isEmpty {
                        Section("Current tasks") {
                            ForEach(current, id: \.1.id) { project, item in
                                WhatsNextRow(item: item, project: project, isCurrent: true)
                            }
                        }
                    }
                    if !dueSoon.isEmpty {
                        Section("Overdue and due soon") {
                            ForEach(dueSoon) { item in
                                WhatsNextRow(item: item, project: item.project, isCurrent: false)
                            }
                        }
                    }
                    if !urgentBugs.isEmpty {
                        Section("High-priority bugs") {
                            ForEach(urgentBugs) { item in
                                WhatsNextRow(item: item, project: item.project, isCurrent: false)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("What's next")
    }
}

private struct WhatsNextRow: View {
    let item: Item
    let project: Project?
    let isCurrent: Bool
    @Environment(Navigator.self) private var nav

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CompletionButton(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                HStack(spacing: 6) {
                    if let project {
                        HStack(spacing: 4) {
                            ProjectIconView(project: project, size: 12)
                            Text(project.name)
                        }
                    }
                    if let list = item.list {
                        Chip(text: list.name, symbol: list.symbol, tint: list.isBugList ? .red : .secondary)
                    }
                    if item.priority != .none { PriorityLabel(priority: item.priority) }
                    if let due = item.dueDate {
                        Label(due.relativeDueText, systemImage: "calendar")
                            .foregroundStyle(item.isOverdue ? .red : .secondary)
                    }
                    if item.touchedByClaude { ClaudeBadge() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") { nav.reveal(item) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { nav.reveal(item) }
        .contextMenu { ItemContextMenu(item: item) }
    }
}
