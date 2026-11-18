import SwiftUI
import SwiftData
import AppKit

@main
struct TwoTonedProjectsApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        Window("TwoToned Projects", id: "main") {
            ContentView()
                .environment(services.nav)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1240, height: 780)
        .modelContainer(services.container)
        .commands {
            AppCommands(nav: services.nav)
        }

        Settings {
            SettingsView()
                .environment(services.nav)
        }
        .modelContainer(services.container)
    }
}

/// Long-lived app objects: the database, navigation state, menu bar and global shortcuts.
@MainActor
final class AppServices {
    let container: ModelContainer
    let nav = Navigator()
    let menuBar: MenuBarController
    let claudeTools: ClaudeTools
    private var bridge: BridgeServer?

    /// The running app's services, for the few places outside SwiftUI that need them.
    private(set) static weak var current: AppServices?

    init() {
        do {
            container = try DataStore.makeContainer()
        } catch {
            fatalError("Couldn't open the TwoToned Projects database: \(error)")
        }
        #if DEBUG
        DemoData.seedIfRequested(in: container.mainContext)
        DemoData.linkFolderIfRequested(in: container.mainContext)
        #endif
        menuBar = MenuBarController(container: container, nav: nav)
        claudeTools = ClaudeTools(container: container)
        let tools = claudeTools
        // Requests from the Claude Code helper arrive on background threads; the
        // data work happens on the main actor, the same place the UI makes changes.
        let server = BridgeServer { data in
            DispatchQueue.main.sync { MainActor.assumeIsolated { tools.handle(data) } }
        }
        server.start()
        bridge = server
        Self.current = self
        // Defer AppKit setup until the app has finished launching.
        DispatchQueue.main.async { [self] in
            menuBar.start()
            registerGlobalShortcuts()
            ClaudeConnection.shared.repairIfNeeded()
            AttachmentCleanup.removeOrphans(in: container.mainContext)
        }
    }

    func stopBridge() {
        bridge?.stop()
        bridge = nil
    }

    /// Re-registers system-wide hotkeys whenever the assigned shortcuts change.
    private func registerGlobalShortcuts() {
        let store = ShortcutStore.shared
        let list: [(Shortcut, () -> Void)] = withObservationTracking {
            ShortcutAction.allCases.filter(\.isGlobal).compactMap { action in
                store.shortcut(for: action).map { shortcut in (shortcut, { [weak self] in self?.perform(action) }) }
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.registerGlobalShortcuts() }
        }
        HotKeyCenter.shared.register(list)
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .quickAdd:
            QuickAddPanel.toggle(container: container)
        case .completeCurrent:
            guard let project = QuickProject.current(in: container.mainContext) else {
                HUD.show("No project yet", symbol: "exclamationmark.circle")
                return
            }
            if let task = Ordering.currentTask(for: project) {
                ProjectActions.complete(task)
                HUD.show("Completed \u{201C}\(task.title)\u{201D}")
            } else {
                HUD.show("\(project.name) is all caught up", symbol: "checkmark.seal")
            }
        case .toggleMenuBar:
            if !menuBar.toggleFromShortcut() {
                HUD.show("Turn on the menu bar in Settings first", symbol: "menubar.rectangle")
            }
        case .openApp:
            nav.showMainWindow()
        case .newProject:
            nav.showMainWindow()
            nav.showNewProject = true
        }
    }
}

struct AppCommands: Commands {
    let nav: Navigator
    private var store: ShortcutStore { .shared }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About TwoToned Projects") {
                let credits = NSAttributedString(
                    string: "By TwoToned Studios\nProjects, tasks, and bugs, right on your Mac.",
                    attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                                 .paragraphStyle: {
                                     let style = NSMutableParagraphStyle()
                                     style.alignment = .center
                                     return style
                                 }()])
                NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
                NSApp.activate()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { nav.showNewProject = true }
                .keyboardShortcut(store.keyboardShortcut(for: .newProject))
        }
    }
}

/// Shared navigation state (sidebar selection, jump-to-item requests, sheets).
@Observable
final class Navigator {
    var selection: SidebarSelection? = .whatsNext
    /// When set, the project view selects and reveals this item once it appears.
    var pendingItemID: UUID?
    var showNewProject = false

    /// Captured from the main window so AppKit code (menu bar, shortcuts) can reopen it.
    @ObservationIgnored var openMainWindowAction: (() -> Void)?

    func reveal(_ item: Item) {
        guard let project = item.project else { return }
        selection = .project(project.id)
        pendingItemID = item.id
    }

    func showMainWindow() {
        NSApp.activate()
        openMainWindowAction?()
    }
}

enum SidebarSelection: Hashable {
    case whatsNext
    case brainstorm
    case project(UUID)
}
