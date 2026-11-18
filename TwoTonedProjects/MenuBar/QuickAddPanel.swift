import AppKit
import SwiftUI
import SwiftData

/// A small Spotlight-style panel for adding an item from anywhere (global shortcut).
@MainActor
enum QuickAddPanel {
    private static var panel: FloatingPanel?

    static func toggle(container: ModelContainer) {
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        let panel = FloatingPanel(width: 460) {
            QuickAddView { item in
                Self.panel?.close()
                if let list = item.list {
                    HUD.show("Added to \(list.name)", symbol: "plus.circle.fill")
                }
            }
            .modelContainer(container)
        }
        panel.onClose = { Self.panel = nil }
        self.panel = panel
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.show(top: visible.maxY - visible.height * 0.22, centerX: visible.midX, on: screen)
    }
}

private struct QuickAddView: View {
    var onAdded: (Item) -> Void

    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @AppStorage(Prefs.quickProjectID) private var projectID = ""

    private var project: Project? { QuickProject.resolve(id: projectID, in: projects) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProjectPickerMenu(projects: projects, selected: project) { projectID = $0.id.uuidString }
            if let project {
                AddItemBar(project: project, fixedList: nil, autoFocus: true, onAdd: onAdded)
                    .id(project.id)
                Text("Prefix with a list name like \u{201C}b:\u{201D}, add \u{201C}!high\u{201D} for priority. Esc closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Create a project in TwoToned Projects first.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}
