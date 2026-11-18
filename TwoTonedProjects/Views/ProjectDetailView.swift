import SwiftUI
import SwiftData
import AppKit

enum ProjectTab: Hashable {
    case upNext
    case list(UUID)
    case done
    case files
    case overview
    case activity
}

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(Navigator.self) private var nav

    @State private var tab: ProjectTab = .upNext
    @State private var selectedItemID: UUID?
    /// Open by default and remembered. Creating the panel together with the view also avoids a
    /// macOS layout bug where a panel opened later starts too narrow and gets cut off.
    @AppStorage("inspector.visible") private var showInspector = true
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(project.status.title)
        .inspector(isPresented: $showInspector) {
            Group {
                if let item = selectedItem {
                    ItemInspector(item: item) { selectedItemID = nil }
                } else {
                    ContentUnavailableView("No item selected", systemImage: "sidebar.right",
                                           description: Text("Select an item to see its details."))
                }
            }
            .inspectorColumnWidth(min: 250, ideal: 320, max: 460)
        }
        .toolbar {
            ToolbarItem {
                BackupButton(project: project)
            }
            ToolbarItem {
                Button { showSettings = true } label: { Label("Project settings", systemImage: "slider.horizontal.3") }
                    .help("Project settings")
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help("Show or hide item details")
            }
        }
        .sheet(isPresented: $showSettings) { ProjectSettingsSheet(project: project) }
        .onChange(of: selectedItemID) { _, new in
            if new != nil { showInspector = true }
        }
        .onAppear(perform: consumePendingItem)
        .onChange(of: nav.pendingItemID) { consumePendingItem() }
        .onChange(of: project.folders.isEmpty) { _, empty in
            if empty, tab == .files || tab == .overview { tab = .upNext }
        }
        .onChange(of: project.lists?.count) {
            // If the selected list was deleted, fall back to Up Next.
            if case .list(let id) = tab, !(project.lists ?? []).contains(where: { $0.id == id }) { tab = .upNext }
        }
    }

    private var selectedItem: Item? {
        guard let selectedItemID else { return nil }
        return project.allItems.first { $0.id == selectedItemID }
    }

    private func consumePendingItem() {
        guard let id = nav.pendingItemID, let item = project.allItems.first(where: { $0.id == id }) else { return }
        nav.pendingItemID = nil
        if item.isCompleted {
            tab = .done
        } else if item.list?.includeInUpNext == true {
            tab = .upNext
        } else if let list = item.list {
            tab = .list(list.id)
        }
        selectedItemID = id
        showInspector = true
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ProjectIconView(project: project, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Label(project.status.title, systemImage: project.status.symbol)
                    if let url = URL(string: project.githubURL), !project.githubURL.isEmpty {
                        Link(destination: url) {
                            Label("GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    if let folder = project.primaryFolder {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        } label: {
                            Label(folder.displayPath, systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.link)
                        .help("Show in Finder")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TabPill(title: "Up Next", symbol: "list.number", count: Ordering.upNext(for: project).count,
                        isSelected: tab == .upNext) { tab = .upNext }
                ForEach(project.sortedLists, id: \.id) { list in
                    TabPill(title: list.name, symbol: list.symbol, count: list.openItems.count,
                            isSelected: tab == .list(list.id)) { tab = .list(list.id) }
                }
                TabPill(title: "Done", symbol: "checkmark.circle",
                        count: nil, isSelected: tab == .done) { tab = .done }
                TabPill(title: "Activity", symbol: "clock.arrow.circlepath",
                        count: nil, isSelected: tab == .activity) { tab = .activity }
                if !project.folders.isEmpty {
                    Divider().frame(height: 16).padding(.horizontal, 4)
                    TabPill(title: "Files", symbol: "photo.on.rectangle", count: nil,
                            isSelected: tab == .files) { tab = .files }
                    TabPill(title: "Overview", symbol: "info.circle", count: nil,
                            isSelected: tab == .overview) { tab = .overview }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .upNext:
            ItemListView(project: project, list: nil, selection: $selectedItemID)
        case .list(let id):
            if let list = project.sortedLists.first(where: { $0.id == id }) {
                ItemListView(project: project, list: list, selection: $selectedItemID)
                    .id(list.id)
            }
        case .done:
            DoneView(project: project, selection: $selectedItemID)
        case .files:
            FilesView(project: project)
        case .overview:
            OverviewView(project: project)
        case .activity:
            ActivityView(project: project)
        }
    }
}

private struct TabPill: View {
    let title: String
    let symbol: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.brandBlueText : .secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.brandBlueText : .primary)
            .background {
                Capsule().fill(isSelected ? Color.brandBlue.opacity(0.16) : .clear)
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
