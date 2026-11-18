import AppKit
import SwiftUI
import SwiftData

/// Owns the optional menu bar item and its panel.
///
/// Everything is event-driven: the label refreshes only when the data it shows
/// changes (via Observation) or when preferences change. No timers.
@MainActor
final class MenuBarController: NSObject {
    private let container: ModelContainer
    private let nav: Navigator
    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var observers: [NSObjectProtocol] = []
    private var lastTitle: String?

    init(container: ModelContainer, nav: Navigator) {
        self.container = container
        self.nav = nav
    }

    var isEnabled: Bool { statusItem != nil }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        })
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLabel() }
        })
        applySettings()
    }

    /// Removes the menu bar item for good (used by "Remove all TwoToned data").
    func shutdown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.close()
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }

    private func applySettings() {
        let enabled = UserDefaults.standard.bool(forKey: Prefs.menuBarEnabled)
        if enabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = MenuBarIcon.image
            item.button?.imagePosition = .imageLeading
            item.button?.target = self
            item.button?.action = #selector(togglePanel)
            item.button?.setAccessibilityLabel("TwoToned Projects")
            statusItem = item
            lastTitle = nil
        } else if !enabled, let item = statusItem {
            panel?.close()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        refreshLabel()
    }

    /// Recomputes the label and re-arms observation of exactly the data it read.
    private func refreshLabel() {
        guard let button = statusItem?.button else { return }
        let title = withObservationTracking {
            labelText()
        } onChange: { [weak self] in
            Task { @MainActor in self?.refreshLabel() }
        }
        guard title != lastTitle else { return }
        lastTitle = title
        button.title = title.isEmpty ? "" : " \(title)"
        button.toolTip = title.isEmpty ? "TwoToned Projects" : title
    }

    private func labelText() -> String {
        guard Prefs.labelStyle == .task,
              let project = QuickProject.current(in: container.mainContext),
              let task = Ordering.currentTask(for: project) else { return "" }
        let limit = 32
        return task.title.count > limit ? String(task.title.prefix(limit - 1)) + "\u{2026}" : task.title
    }

    @objc func togglePanel() {
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        guard let button = statusItem?.button, let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let panel = makePanel()
        panel.show(top: buttonFrame.minY - 4, centerX: buttonFrame.midX, on: window.screen)
        button.highlight(true)
    }

    private func makePanel() -> FloatingPanel {
        // Built fresh each time and released on close, so it costs nothing while hidden.
        let panel = FloatingPanel(width: 340) {
            MenuBarPanelView { [weak self] project in self?.openInApp(project) }
                .modelContainer(container)
                .environment(nav)
        }
        panel.onClose = { [weak self] in
            self?.statusItem?.button?.highlight(false)
            self?.panel = nil
        }
        self.panel = panel
        return panel
    }

    func openInApp(_ project: Project?) {
        panel?.close()
        if let project { nav.selection = .project(project.id) }
        nav.showMainWindow()
    }

    /// Toggles the panel from a global shortcut. Returns false if the menu bar item is off.
    @discardableResult
    func toggleFromShortcut() -> Bool {
        guard statusItem != nil else { return false }
        togglePanel()
        return true
    }
}

enum MenuBarIcon {
    /// The TwoToned mark as a template image, so macOS tints it to match the menu bar.
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let logo = NSImage(named: "StudioLogo") else { return false }
            let s = logo.size.width / 3000
            // Crop to the mark itself (the source image has generous padding).
            let crop = NSRect(x: 480 * s, y: 740 * s, width: 2040 * s, height: 1520 * s)
            logo.draw(in: rect, from: crop, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TwoToned Projects"
        return image
    }()
}
