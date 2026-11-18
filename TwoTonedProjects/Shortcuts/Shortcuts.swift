import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Actions you can assign keyboard shortcuts to. All start unassigned.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case quickAdd, completeCurrent, toggleMenuBar, openApp, newProject

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickAdd: "Quick add"
        case .completeCurrent: "Complete current task"
        case .toggleMenuBar: "Show menu bar panel"
        case .openApp: "Open TwoToned Projects"
        case .newProject: "New project"
        }
    }

    var detail: String {
        switch self {
        case .quickAdd: "Opens a small add field from any app."
        case .completeCurrent: "Checks off the current task of the menu bar project, from any app."
        case .toggleMenuBar: "Opens the menu bar panel from any app (menu bar must be on)."
        case .openApp: "Brings the main window forward from any app."
        case .newProject: "Works while TwoToned Projects is in front."
        }
    }

    /// Global shortcuts work from any app; the rest only inside this app.
    var isGlobal: Bool { self != .newProject }
}

nonisolated struct Shortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value (command/option/control/shift only).
    var modifiers: UInt
    /// Lowercased base character, used for in-app menu shortcuts.
    var character: String
    var display: String

    static func == (a: Shortcut, b: Shortcut) -> Bool { a.keyCode == b.keyCode && a.modifiers == b.modifiers }
    func hash(into hasher: inout Hasher) { hasher.combine(keyCode); hasher.combine(modifiers) }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Require a real modifier so shortcuts never swallow normal typing.
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = flags.rawValue
        character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += Self.keyName(code: Int(event.keyCode), fallback: event.charactersIgnoringModifiers ?? "?")
        display = text
    }

    private static func keyName(code: Int, fallback: String) -> String {
        let names: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return names[code] ?? fallback.uppercased()
    }
}

/// Stores assigned shortcuts in UserDefaults. Observable so menus and settings update live.
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()

    private(set) var shortcuts: [ShortcutAction: Shortcut] = [:]

    private init() {
        for action in ShortcutAction.allCases {
            if let data = UserDefaults.standard.data(forKey: key(action)),
               let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) {
                shortcuts[action] = shortcut
            }
        }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? { shortcuts[action] }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if let shortcut {
            // One shortcut, one action: clear it from anything else using it.
            for (other, existing) in shortcuts where other != action && existing == shortcut {
                shortcuts[other] = nil
                UserDefaults.standard.removeObject(forKey: key(other))
            }
            shortcuts[action] = shortcut
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: key(action))
        } else {
            shortcuts[action] = nil
            UserDefaults.standard.removeObject(forKey: key(action))
        }
    }

    /// SwiftUI menu shortcut for in-app actions, if one is assigned.
    func keyboardShortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        guard let s = shortcuts[action], let char = s.character.first else { return nil }
        var mods: SwiftUI.EventModifiers = []
        if s.flags.contains(.command) { mods.insert(.command) }
        if s.flags.contains(.option) { mods.insert(.option) }
        if s.flags.contains(.control) { mods.insert(.control) }
        if s.flags.contains(.shift) { mods.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(char), modifiers: mods)
    }

    private func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }
}

/// System-wide hotkeys via Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission and costs nothing until a key is pressed.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false
    private var paused = false
    private var registrations: [(Shortcut, () -> Void)] = []

    func register(_ list: [(Shortcut, () -> Void)]) {
        registrations = list
        apply()
    }

    /// Temporarily releases all hotkeys (while recording a new shortcut).
    func pause() { paused = true; apply() }
    func resume() { paused = false; apply() }

    private func apply() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
        guard !paused, !registrations.isEmpty else { return }
        installHandlerIfNeeded()
        for (index, (shortcut, handler)) in registrations.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x5454_5052), id: id) // 'TTPR'
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                handlers[id] = handler
            }
        }
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
