import SwiftUI
import SwiftData

struct ItemRow: View {
    let item: Item
    var isCurrent = false
    var showsList = false

    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CompletionButton(item: item)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .lineLimit(2)
                metadata
            }

            Spacer(minLength: 8)

            if isCurrent {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandBlueText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.brandBlue.opacity(0.16), in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isCurrent ? 6 : 0)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.brandBlue, lineWidth: 1.5)
                    .padding(.horizontal, -2)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { ItemContextMenu(item: item) }
    }

    @ViewBuilder
    private var metadata: some View {
        let subtasksDone = item.subtasks.filter(\.isDone).count
        let hasMeta = showsList || item.priority != .none || item.dueDate != nil || !item.subtasks.isEmpty
            || !item.tags.isEmpty || item.touchedByClaude || !item.notes.isEmpty
        if hasMeta {
            HStack(spacing: 6) {
                if showsList, let list = item.list {
                    Chip(text: list.name, symbol: list.symbol, tint: list.isBugList ? .red : .secondary)
                }
                if item.priority != .none {
                    PriorityLabel(priority: item.priority)
                }
                if let due = item.dueDate {
                    Label(due.relativeDueText, systemImage: "calendar")
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }
                if !item.subtasks.isEmpty {
                    Label("\(subtasksDone)/\(item.subtasks.count)", systemImage: "checklist")
                        .foregroundStyle(.secondary)
                }
                if !item.notes.isEmpty {
                    Image(systemName: "note.text").foregroundStyle(.secondary)
                }
                ForEach(item.tags.prefix(3), id: \.self) { tag in
                    Text("#\(tag)").foregroundStyle(.secondary)
                }
                if item.touchedByClaude { ClaudeBadge() }
            }
            .font(.caption)
            .labelStyle(.titleAndIcon)
        }
    }
}

struct PriorityLabel: View {
    let priority: Priority

    var body: some View {
        if let symbol = priority.symbol {
            Label(priority.title, systemImage: symbol)
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch priority {
        case .urgent: .red
        case .high: .orange
        case .medium: .yellow
        default: .secondary
        }
    }
}

struct CompletionButton: View {
    let item: Item

    var body: some View {
        Button {
            withAnimation(.snappy) { ProjectActions.toggleComplete(item) }
        } label: {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.isCompleted ? Color.brandBlue : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(item.isCompleted ? "Reopen" : "Mark complete")
        .accessibilityLabel(item.isCompleted ? "Reopen \(item.title)" : "Complete \(item.title)")
    }
}

struct ItemContextMenu: View {
    let item: Item
    @Environment(\.modelContext) private var context

    var body: some View {
        Button(item.isCompleted ? "Reopen" : "Mark complete") {
            withAnimation { ProjectActions.toggleComplete(item) }
        }
        if !item.isCompleted, item.list?.includeInUpNext == true, let project = item.project {
            Button("Make current task") {
                withAnimation { Ordering.makeCurrent(item, in: project) }
            }
        }
        if let project = item.project {
            Menu("Move to") {
                ForEach(project.sortedLists, id: \.id) { list in
                    Button {
                        withAnimation { ProjectActions.move(item, to: list) }
                    } label: {
                        Label(list.name, systemImage: list.symbol)
                    }
                    .disabled(list === item.list)
                }
            }
        }
        Menu("Priority") {
            ForEach(Priority.allCases.reversed()) { priority in
                Button {
                    item.priority = priority
                    item.touch()
                } label: {
                    if item.priority == priority {
                        Label(priority.title, systemImage: "checkmark")
                    } else {
                        Text(priority.title)
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            withAnimation { ProjectActions.delete(item, context: context) }
        }
    }
}
