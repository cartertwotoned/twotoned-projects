import Foundation

/// A folder linked to a project. The app only ever reads from it.
nonisolated struct FolderLink: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var path: String
    /// Bookmark so access survives renames/moves (and a future sandboxed App Store build).
    var bookmark: Data?
    var isPrimary: Bool = false

    init(url: URL, isPrimary: Bool) {
        path = url.standardizedFileURL.path
        bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        self.isPrimary = isPrimary
    }

    /// Resolves the folder, following it if it was moved or renamed.
    var url: URL {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                       relativeTo: nil, bookmarkDataIsStale: &stale) {
                return resolved
            }
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                       relativeTo: nil, bookmarkDataIsStale: &stale) {
                return resolved
            }
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var name: String { (path as NSString).lastPathComponent }

    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

/// A file attached to an item: either a reference to a file inside a linked folder,
/// or a copy stored in the app's own data folder.
nonisolated struct Attachment: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// Absolute path for references; file name inside the attachments folder for stored copies.
    var path: String
    var isStoredCopy: Bool

    var url: URL {
        isStoredCopy
            ? DataStore.attachmentsDirectory.appending(path: id.uuidString).appending(path: path)
            : URL(fileURLWithPath: path)
    }
}
