import SwiftUI
import SwiftData

/// Recent changes to a project, by you or Claude.
struct ActivityView: View {
    let project: Project
    @Environment(\.modelContext) private var context
    @Environment(Navigator.self) private var nav
    @State private var confirmClear = false

    private var groups: [(day: Date, entries: [ActivityEntry])] {
        let entries = (project.activity ?? []).sorted { $0.date > $1.date }
        let byDay = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { ($0, byDay[$0]!) }
    }

    var body: some View {
        let groups = groups
        if groups.isEmpty {
            ContentUnavailableView {
                Label("No activity yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Items you or Claude add, complete, move, or delete show up here.")
            }
        } else {
            List {
                ForEach(groups, id: \.day) { group in
                    Section(dayTitle(group.day)) {
                        ForEach(group.entries) { entry in row(entry) }
                    }
                }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("Keeps the latest \(ActivityLog.maxEntriesPerProject) changes.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear activity…") { confirmClear = true }
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .confirmationDialog("Clear this project's activity?", isPresented: $confirmClear) {
                Button("Clear activity", role: .destructive) {
                    for entry in project.activity ?? [] { context.delete(entry) }
                }
            } message: {
                Text("Only the log is cleared. Your items aren't changed.")
            }
        }
    }

    private func row(_ entry: ActivityEntry) -> some View {
        let item = entry.itemID.flatMap { id in project.allItems.first { $0.id == id } }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.symbol)
                .foregroundStyle(entry.author == .claude ? Color.brandPurpleText : .secondary)
                .frame(width: 18)
            Text(entry.summary)
            if entry.author == .claude { ClaudeBadge() }
            Spacer()
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let item { nav.reveal(item) } }
        .help(item == nil ? "" : "Double-click to show the item")
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
