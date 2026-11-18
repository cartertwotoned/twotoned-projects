import AppKit
import SwiftUI

/// A popover-style panel that can take keyboard input without activating the app,
/// so typing into it never pulls the main window in front of your work.
final class FloatingPanel: NSPanel {
    var onClose: (() -> Void)?
    /// Keeps the panel's top edge fixed while its SwiftUI content grows or shrinks.
    var anchorTop: CGFloat?

    init<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = content()
            .ignoresSafeArea()
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                self?.fit(to: size)
            }
        contentView = NSHostingView(rootView: root)
    }

    override var canBecomeKey: Bool { true }

    /// Clicking anywhere else dismisses the panel, like a popover.
    override func resignKey() {
        super.resignKey()
        if isVisible { close() }
    }

    /// Escape closes the panel.
    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        super.close()
        onClose?()
    }

    private func fit(to size: CGSize) {
        guard size.height > 0 else { return }
        let top = anchorTop ?? frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Shows the panel with its top edge at `top`, horizontally centred on `centerX`,
    /// kept inside the visible area of the screen.
    func show(top: CGFloat, centerX: CGFloat, on screen: NSScreen?) {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let width = frame.width
        var x = centerX - width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        anchorTop = min(top, visible.maxY)
        setFrameTopLeftPoint(NSPoint(x: x, y: anchorTop!))
        makeKeyAndOrderFront(nil)
    }
}

/// A brief, non-interactive confirmation bubble (e.g. "Completed …").
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let view = HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color.brandBlue)
            Text(message).lineLimit(1)
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self.panel === panel { self.panel = nil }
        }
    }
}
