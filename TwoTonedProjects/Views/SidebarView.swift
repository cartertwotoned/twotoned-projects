import SwiftUI
import SwiftData

struct SidebarView: View {
    let projects: [Project]
    @Environment(Navigator.self) private var nav
    @Environment(\.modelContext) private var context

    @AppStorage("sidebar.expanded.released") private var releasedExpanded = true
    @AppStorage("sidebar.expanded.paused") private var pausedExpanded = false
    @AppStorage("sidebar.expanded.archived") private var archivedExpanded = false

    @Query private var brainstorm: [BrainstormIdea]
    private var brainstormCount: Int { brainstorm.count }

    @State private var editing: Project?
    @State private var deleting: Project?

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.selection) {
            Label("What's next", systemImage: "sparkles")
                .tag(SidebarSelection.whatsNext)
            Label("Brainstorm", systemImage: "lightbulb.max")
                .badge(brainstormCount)
                .tag(SidebarSelection.brainstorm)

            Section("Active") {
                ForEach(projects(with: .active)) { row(for: $0) }
                    .onMove { move(in: .active, from: $0, to: $1) }
            }

            section(.released, expanded: $releasedExpanded)
            section(.paused, expanded: $pausedExpanded)
            section(.archived, expanded: $archivedExpanded)
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                StudioBadge()
            }
            // A label, not a button: no glass bubble behind it.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                Button { nav.showNewProject = true } label: {
                    Label("New project", systemImage: "plus")
                }
                .help("New project")
            }
        }
        .sheet(item: $editing) { ProjectSettingsSheet(project: $0) }
        .confirmationDialog(
            "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete project", role: .destructive) {
                if let deleting {
                    if nav.selection == .project(deleting.id) { nav.selection = .whatsNext }
                    ProjectActions.deleteProject(deleting, context: context)
                }
                deleting = nil
            }
        } message: {
            Text("All of its lists and items are deleted too. To keep it out of the way instead, archive it.")
        }
    }

    @ViewBuilder
    private func section(_ status: ProjectStatus, expanded: Binding<Bool>) -> some View {
        let items = projects(with: status)
        if !items.isEmpty {
            Section(isExpanded: expanded) {
                ForEach(items) { row(for: $0) }
                    .onMove { move(in: status, from: $0, to: $1) }
            } header: {
                Text("\(status.title) (\(items.count))")
            }
        }
    }

    private func projects(with status: ProjectStatus) -> [Project] {
        projects.filter { $0.status == status }
    }

    private func row(for project: Project) -> some View {
        Label {
            Text(project.name)
        } icon: {
            ProjectIconView(project: project, size: 18)
        }
        .badge(Ordering.upNext(for: project).count)
        .tag(SidebarSelection.project(project.id))
        .contextMenu {
            Button("Edit project…") { editing = project }
            Menu("Status") {
                ForEach(ProjectStatus.allCases) { status in
                    Button {
                        project.status = status
                    } label: {
                        if project.status == status {
                            Label(status.title, systemImage: "checkmark")
                        } else {
                            Text(status.title)
                        }
                    }
                }
            }
            if let url = URL(string: project.githubURL), !project.githubURL.isEmpty {
                Link("Open on GitHub", destination: url)
            }
            Divider()
            Button("Back up now") { Task { await BackupService.shared.backUp(project) } }
            Button("Export as Markdown…") { FileTransfers.exportMarkdown(project) }
            Divider()
            Button("Delete project…", role: .destructive) { deleting = project }
        }
    }

    private func move(in status: ProjectStatus, from source: IndexSet, to destination: Int) {
        var group = projects(with: status)
        group.move(fromOffsets: source, toOffset: destination)
        let slots = projects(with: status).map(\.sortIndex).sorted()
        for (project, slot) in zip(group, slots) { project.sortIndex = slot }
    }
}

/// TwoToned Studios mark and the app name, shown in the title bar.
private struct StudioBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("StudioLogoSmall")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text("TwoToned")
                .font(.headline)
        }
        .fixedSize()
        .help("TwoToned Projects by TwoToned Studios")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TwoToned Projects by TwoToned Studios")
    }
}
