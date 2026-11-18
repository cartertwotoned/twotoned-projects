import SwiftUI
import SwiftData

/// Contents of the menu bar panel: project picker, current task, more tasks, quick add.
struct MenuBarPanelView: View {
    var onOpenInApp: (Project?) -> Void

    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @AppStorage(Prefs.quickProjectID) private var projectID = ""
    @State private var showMore = false

    private var project: Project? { QuickProject.resolve(id: projectID, in: projects) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let project {
                content(for: project)
            } else {
                Text("Create a project in TwoToned Projects to use the menu bar.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            ProjectPickerMenu(projects: projects, selected: project) { projectID = $0.id.uuidString }
            Spacer()
            Button { onOpenInApp(project) } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Open in TwoToned Projects")
            .accessibilityLabel("Open in TwoToned Projects")
        }
    }

    @ViewBuilder
    private func content(for project: Project) -> some View {
        let upNext = Ordering.upNext(for: project)
        if let current = upNext.first {
            CurrentTaskCard(item: current)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal").foregroundStyle(Color.brandBlue)
                Text("All caught up").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }

        let rest = Array(upNext.dropFirst())
        if !rest.isEmpty {
            Button {
                withAnimation(.snappy) { showMore.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showMore ? 90 : 0))
                    Text(showMore ? "Show less" : "Show more (\(rest.count))")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rest) { item in
                            CompactItemRow(item: item)
                            if item.id != rest.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .scrollBounceBehavior(.basedOnSize)
            }
        }

        AddItemBar(project: project, fixedList: nil, compact: true, autoFocus: false)
    }
}

struct ProjectPickerMenu: View {
    let projects: [Project]
    let selected: Project?
    var onSelect: (Project) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let selected { ProjectIconView(project: selected, size: 18) }
            menu
        }
    }

    private var menu: some View {
        Menu {
            ForEach(ProjectStatus.allCases) { status in
                let group = projects.filter { $0.status == status }
                if !group.isEmpty {
                    Section(status.title) {
                        ForEach(group, id: \.id) { project in
                            Button {
                                onSelect(project)
                            } label: {
                                if project === selected {
                                    Label(project.name, systemImage: "checkmark")
                                } else {
                                    Text(project.name)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Text(selected?.name ?? "Choose project")
                .font(.headline)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// The big "current task" card with a one-click complete button.
private struct CurrentTaskCard: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brandBlueText)
            Text(item.title)
                .font(.title3.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
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
            Button {
                withAnimation(.snappy) { ProjectActions.complete(item) }
            } label: {
                Label("Complete", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.brandBlue)
        }
        .padding(12)
        .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.brandBlue.opacity(0.6), lineWidth: 1)
        }
    }
}

private struct CompactItemRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CompletionButton(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(2)
                HStack(spacing: 6) {
                    if let list = item.list { Text(list.name) }
                    if item.priority != .none { PriorityLabel(priority: item.priority) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
