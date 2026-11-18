import SwiftUI
import SwiftData

/// Shows either Up Next (`list == nil`) or a single list's open items.
struct ItemListView: View {
    let project: Project
    let list: TaskList?
    @Binding var selection: UUID?

    @Environment(\.modelContext) private var context

    private var items: [Item] {
        if let list { Ordering.openItems(in: list) } else { Ordering.upNext(for: project) }
    }

    var body: some View {
        let items = items
        let currentID = Ordering.currentTask(for: project)?.id
        VStack(spacing: 0) {
            AddItemBar(project: project, fixedList: list) { selection = $0.id }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            if items.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(items) { item in
                        ItemRow(item: item, isCurrent: item.id == currentID, showsList: list == nil)
                            .tag(item.id)
                    }
                    .onMove { Ordering.move(items, from: $0, to: $1) }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .onDeleteCommand {
                    if let selected = items.first(where: { $0.id == selection }) {
                        ProjectActions.delete(selected, context: context)
                        selection = nil
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if items.count > 1 {
                HStack {
                    Text(footerText(count: items.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-sort by priority") {
                        withAnimation { Ordering.resort(items) }
                    }
                    .help("Order by priority, then bugs first, then oldest first. Drag items to reorder by hand.")
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func footerText(count: Int) -> String {
        "\(count) open"
    }

    @ViewBuilder
    private var emptyState: some View {
        if let list {
            ContentUnavailableView {
                Label("\(list.name) is clear", systemImage: list.symbol)
            } description: {
                Text("Add an item above.")
            }
        } else if project.sortedLists.contains(where: \.includeInUpNext) {
            ContentUnavailableView {
                Label("All caught up", systemImage: "checkmark.circle")
            } description: {
                Text("Everything in Up Next is done. Add something above, or promote an idea.")
            }
        } else {
            ContentUnavailableView {
                Label("No lists feed Up Next", systemImage: "list.number")
            } description: {
                Text("Turn on \u{201C}Include in Up Next\u{201D} for a list in project settings.")
            }
        }
    }
}

/// Text field for adding items, with a list picker and quick-add syntax.
struct AddItemBar: View {
    let project: Project
    /// When set, items always go into this list (list tabs). Otherwise the picker chooses.
    let fixedList: TaskList?
    /// Shorter placeholder for narrow places like the menu bar panel.
    var compact = false
    var autoFocus = false
    var onAdd: (Item) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var pickedListID: UUID?
    @FocusState private var focused: Bool

    private var targetList: TaskList? {
        if let fixedList { return fixedList }
        let lists = project.sortedLists
        return lists.first { $0.id == pickedListID } ?? project.defaultList
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.brandBlue)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Add item (or press Return)")
            .accessibilityLabel("Add item")
            WrappingTextField(title: placeholder, text: $text, lines: 1...8, onSubmit: add)
                .textFieldStyle(.plain)
                .focused($focused)
                .help(fixedList == nil
                      ? "Type a list prefix like \u{201C}b:\u{201D} for Bugs, and \u{201C}!high\u{201D} for priority."
                      : "Add \u{201C}!high\u{201D} (or !low, !medium, !urgent) to set priority.")
                .onAppear { if autoFocus { focused = true } }
            if fixedList == nil {
                Menu {
                    ForEach(project.sortedLists, id: \.id) { list in
                        Button {
                            pickedListID = list.id
                        } label: {
                            Label(list.name, systemImage: list.symbol)
                        }
                    }
                } label: {
                    Label(targetList?.name ?? "List", systemImage: targetList?.symbol ?? "tray")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("List for new items. You can also type a prefix like \u{201C}b:\u{201D} for Bugs.")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: String {
        if let fixedList { return "Add to \(fixedList.name)" }
        if compact { return "Add an item" }
        return "Add an item (try \u{201C}b: crash on launch !high\u{201D})"
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let (result, prefixedList) = QuickAddParser.resolve(trimmed, in: project)
        guard !result.title.isEmpty, let list = prefixedList ?? targetList else { return }
        let item = ProjectActions.addItem(result, to: list, in: project, context: context)
        text = ""
        focused = true
        onAdd(item)
    }
}
