import AppKit
import SwiftData

/// "Remove all TwoToned data": deletes everything the app has created on this Mac,
/// then quits. Afterwards, moving the app to the Trash leaves nothing behind.
extension AppServices {
    func removeAllData() async {
        // 1. Remove the Claude Code connection (the only thing outside the app's own folders).
        let connection = ClaudeConnection.shared
        connection.refresh()
        if connection.status != .notConnected { await connection.disconnect() }

        // 2. Stop everything that could write while we clean up.
        HotKeyCenter.shared.register([])
        menuBar.shutdown()
        stopBridge()
        container.mainContext.autosaveEnabled = false

        // 3. Delete the app's files: database, attachments, socket, caches, saved state, preferences.
        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser.appending(path: "Library")
        let bundleID = Bundle.main.bundleIdentifier ?? "com.twotonedstudios.projects"
        try? fm.removeItem(at: DataStore.dataDirectory)
        for path in ["Caches/\(bundleID)", "HTTPStorages/\(bundleID)", "Saved Application State/\(bundleID).savedState",
                     "WebKit/\(bundleID)"] {
            try? fm.removeItem(at: library.appending(path: path))
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        let plist = library.appending(path: "Preferences/\(bundleID).plist").path
        try? fm.removeItem(atPath: plist)
        // macOS's preferences service can write an empty file back as the app exits,
        // so remove it once more shortly after we've quit.
        let sweeper = Process()
        sweeper.executableURL = URL(fileURLWithPath: "/bin/sh")
        sweeper.arguments = ["-c", "sleep 2; rm -f \"$0\"", plist]
        try? sweeper.run()

        // 4. Quit without saving (a normal quit could recreate the database).
        exit(0)
    }
}

/// Deletes copied attachment files that no item refers to any more
/// (for example after an item was deleted). Runs once at launch.
enum AttachmentCleanup {
    @MainActor
    static func removeOrphans(in context: ModelContext) {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: DataStore.attachmentsDirectory.path), !folders.isEmpty
        else { return }
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
        let referenced = Set(items.flatMap { $0.attachments.filter(\.isStoredCopy).map(\.id.uuidString) })
        for folder in folders where !referenced.contains(folder) && UUID(uuidString: folder) != nil {
            try? fm.removeItem(at: DataStore.attachmentsDirectory.appending(path: folder))
        }
    }
}
