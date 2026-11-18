import SwiftUI
import SwiftData

struct DoneView: View {
    let project: Project
    @Binding var selection: UUID?

    @Environment(\.modelContext) private var context
    @State private var confirmClear = false

    private var groups: [(day: Date, items: [Item])] {
        let done = project.allItems.filter(\.isCompleted)
        let byDay = Dictionary(grouping: done) { Calendar.current.startOfDay(for: $0.completedAt ?? .distantPast) }
        return byDay.keys.sorted(by: >).map { day in
            (day, byDay[day]!.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
        }
    }

    var body: some View {
        let groups = groups
        if groups.isEmpty {
            ContentUnavailableView {
                Label("Nothing done yet", systemImage: "checkmark.circle")
            } description: {
                Text("Completed items from every list collect here. You can reopen any of them.")
            }
        } else {
            List(selection: $selection) {
                ForEach(groups, id: \.day) { group in
                    Section(dayTitle(group.day)) {
                        ForEach(group.items) { item in
                            DoneRow(item: item).tag(item.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .onDeleteCommand {
                if let item = project.allItems.first(where: { $0.id == selection }) {
                    ProjectActions.delete(item, context: context)
                    selection = nil
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(groups.reduce(0) { $0 + $1.items.count }) completed")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete all completed…") { confirmClear = true }
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .confirmationDialog("Delete all completed items?", isPresented: $confirmClear) {
                Button("Delete all", role: .destructive) {
                    for item in project.allItems where item.isCompleted { context.delete(item) }
                    selection = nil
                }
            } message: {
                Text("They're permanently deleted. You can undo right after with Edit › Undo.")
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct DoneRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CompletionButton(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let list = item.list { Chip(text: list.name, symbol: list.symbol) }
                    if let date = item.completedAt {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.tertiary)
                    }
                    if item.touchedByClaude { ClaudeBadge() }
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contextMenu { ItemContextMenu(item: item) }
    }
}
