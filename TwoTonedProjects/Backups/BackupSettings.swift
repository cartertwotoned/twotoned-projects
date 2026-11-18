import Foundation

/// App-wide backup preferences.
nonisolated enum BackupSettings {
    static let folderKey = "backup.folderPath"
    static let maxCountKey = "backup.maxCount"
    static let contentsKey = "backup.contents"

    static let defaultMaxCount = 10

    /// iCloud Drive's folder on this Mac, if iCloud Drive is turned on.
    static var iCloudDrive: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where backups go: the chosen folder, or "TwoToned Backups" in iCloud Drive (Documents if iCloud Drive is off).
    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = iCloudDrive ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents")
        return base.appending(path: "TwoToned Backups", directoryHint: .isDirectory)
    }

    /// The folder as people know it: "iCloud Drive › TwoToned Backups" rather than the raw path.
    static var displayPath: String {
        let path = folder.standardizedFileURL.path
        if let cloud = iCloudDrive?.standardizedFileURL.path, path.hasPrefix(cloud) {
            let rest = path.dropFirst(cloud.count).split(separator: "/").joined(separator: " › ")
            return rest.isEmpty ? "iCloud Drive" : "iCloud Drive › \(rest)"
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    static var isInICloud: Bool {
        guard let cloud = iCloudDrive?.standardizedFileURL.path else { return false }
        return folder.standardizedFileURL.path.hasPrefix(cloud)
    }

    /// Backups kept per project; 0 means unlimited.
    static var maxCount: Int {
        UserDefaults.standard.object(forKey: maxCountKey) as? Int ?? defaultMaxCount
    }

    static var contents: BackupContents {
        BackupContents(rawValue: UserDefaults.standard.string(forKey: contentsKey) ?? "") ?? .everything
    }
}

/// What a backup copies from the project's linked folders. TwoToned data is always included.
nonisolated enum BackupContents: String, CaseIterable, Identifiable, Sendable {
    /// An exact copy of the whole folder: git-ignored files, build output, dependencies, .git, hidden files.
    case everything
    /// Skips build and dependency folders and git-ignored files.
    case skipIgnored
    /// No folder files, just the project's TwoToned data.
    case dataOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Everything in the folder"
        case .skipIgnored: "Skip build, dependency, and git-ignored files"
        case .dataOnly: "TwoToned data only"
        }
    }

    var detail: String {
        switch self {
        case .everything:
            "A complete copy of each linked folder, including git-ignored files, dependencies, build output, and git history, so you can keep working from the backup or restore everything after losing a drive."
        case .skipIgnored:
            "Copies your files but leaves out build and dependency folders (like node_modules) and anything in .gitignore. Smaller and faster to upload, but those files would need to be regenerated."
        case .dataOnly:
            "Only the project's lists, items, and settings. Use this when the code is already safe elsewhere, like on GitHub."
        }
    }
}
