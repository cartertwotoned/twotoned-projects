import AppKit
import SwiftUI

/// Click, then press a key combination to assign it. Esc cancels.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    private var store: ShortcutStore { .shared }

    @State private var recording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(label)
                    .monospaced(store.shortcut(for: action) != nil && !recording)
                    .foregroundStyle(recording ? Color.brandBlueText : .primary)
                    .frame(minWidth: 130)
            }
            .help(recording ? "Press a shortcut with ⌘, ⌥, or ⌃. Esc cancels." : "Click to record a shortcut")

            if store.shortcut(for: action) != nil, !recording {
                Button {
                    store.set(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut")
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private var label: String {
        if recording { return rejected ? "Add ⌘, ⌥, or ⌃" : "Type shortcut…" }
        return store.shortcut(for: action)?.display ?? "Record shortcut"
    }

    private func start() {
        recording = true
        rejected = false
        HotKeyCenter.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            guard let shortcut = Shortcut(event: event) else {
                rejected = true
                NSSound.beep()
                return nil
            }
            store.set(shortcut, for: action)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyCenter.shared.resume()
    }
}
