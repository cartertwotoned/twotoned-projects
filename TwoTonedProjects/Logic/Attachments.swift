import Foundation

/// Adds and removes item attachments.
///
/// Files inside one of the project's linked folders are referenced in place.
/// Files from anywhere else are copied into the app's data folder, so the
/// attachment keeps working (and is removed by "Remove all TwoToned data").
enum Attachments {
    static func add(_ url: URL, to item: Item) {
        let path = url.standardizedFileURL.path
        guard !item.attachments.contains(where: { !$0.isStoredCopy && $0.path == path }) else { return }
        let insideFolder = item.project?.folders.contains { folder in
            path.hasPrefix(folder.url.standardizedFileURL.path + "/")
        } ?? false

        if insideFolder {
            item.attachments.append(Attachment(name: url.lastPathComponent, path: path, isStoredCopy: false))
        } else {
            var attachment = Attachment(name: url.lastPathComponent, path: url.lastPathComponent, isStoredCopy: true)
            let folder = DataStore.attachmentsDirectory.appending(path: attachment.id.uuidString)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: url, to: folder.appending(path: url.lastPathComponent))
            } catch {
                return
            }
            attachment.path = url.lastPathComponent
            item.attachments.append(attachment)
        }
        item.touch()
    }

    static func remove(_ attachment: Attachment, from item: Item) {
        item.attachments.removeAll { $0.id == attachment.id }
        if attachment.isStoredCopy {
            try? FileManager.default.removeItem(at: attachment.url.deletingLastPathComponent())
        }
        item.touch()
    }
}
