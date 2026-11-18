import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(Navigator.self) private var nav
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Project.sortIndex) private var projects: [Project]

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            SidebarView(projects: projects)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            detail
        }
        .sheet(isPresented: $nav.showNewProject) {
            NewProjectSheet()
        }
        .onAppear {
            context.undoManager = undoManager
            nav.openMainWindowAction = { [openWindow] in openWindow(id: "main") }
        }
        .onChange(of: undoManager) { context.undoManager = undoManager }
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.selection {
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                ProjectDetailView(project: project)
                    .id(project.id)
            } else {
                emptyState
            }
        case .brainstorm:
            BrainstormView()
        case .whatsNext, nil:
            if projects.isEmpty {
                emptyState
            } else {
                WhatsNextView(projects: projects)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Start your first project", systemImage: "square.stack.3d.up")
        } description: {
            Text("Projects hold your lists of tasks, bugs, and ideas.")
        } actions: {
            Button("Create project") { nav.showNewProject = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
