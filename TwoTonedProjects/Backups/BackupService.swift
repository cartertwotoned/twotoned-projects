import Foundation
import AppKit
import SwiftData

/// Makes numbered project backups ("Backup 1", "Backup 2", …) in the backup folder,
/// by default in iCloud Drive, which macOS uploads automatically.
///
/// Each backup holds the project's TwoToned data (JSON to re-import, plus a Markdown
/// summary) and, optionally, a copy of its linked folders without build/dependency
/// folders or git-ignored files. Work runs in the background at low priority.
@MainActor
@Observable
final class BackupService {
    static let shared = BackupService()

    private(set) var running: Set<UUID> = []
    @ObservationIgnored private var scheduledAuto: Set<UUID> = []

    enum Reason { case manual, automatic }

    struct Outcome: Sendable {
        let number: Int
        let folder: URL
    }

    func isRunning(_ project: Project) -> Bool { running.contains(project.id) }

    /// Folder holding this project's backups.
    func folder(for project: Project) -> URL {
        BackupSettings.folder.appending(path: Self.safeName(project.name), directoryHint: .isDirectory)
    }

    @discardableResult
    func backUp(_ project: Project, reason: Reason = .manual) async -> Result<Outcome, Error> {
        guard !running.contains(project.id) else { return .failure(CocoaError(.userCancelled)) }
        running.insert(project.id)
        defer { running.remove(project.id) }

        // Snapshot everything on the main actor, then do the file work in the background.
        let data: Data
        do { data = try Backup.encode([project]) } catch { return .failure(error) }
        let summary = MarkdownExport.markdown(for: project)
        let contents = BackupSettings.contents
        let roots = contents == .dataOnly ? [] : project.folders.map(\.url)
        let destination = folder(for: project)
        let maxCount = BackupSettings.maxCount

        let result = await Task.detached(priority: .utility) {
            Result {
                try BackupWriter.write(data: data, summary: summary, roots: roots, skipIgnored: contents == .skipIgnored,
                                       into: destination, keep: maxCount)
            }
        }.value

        if case .success(let outcome) = result {
            project.lastBackupAt = .now
            ActivityLog.record(project, .user,
                               "\(reason == .automatic ? "Automatic backup" : "Backed up") (Backup \(outcome.number))",
                               symbol: "icloud.and.arrow.up")
            if reason == .manual {
                HUD.show("Backed up \(project.name) (Backup \(outcome.number))", symbol: "icloud.and.arrow.up")
            }
        } else if case .failure(let error) = result, reason == .manual {
            HUD.show("Backup failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
        return result
    }

    /// Called when an item is completed. If the project has automatic backups on and enough time
    /// has passed, backs up after a short pause, so checking off several items makes one backup.
    func itemCompleted(in project: Project) {
        guard project.autoBackup, !scheduledAuto.contains(project.id) else { return }
        let interval = TimeInterval(max(1, project.autoBackupMinutes) * 60)
        if let last = project.lastBackupAt, Date.now.timeIntervalSince(last) < interval { return }
        scheduledAuto.insert(project.id)
        Task {
            try? await Task.sleep(for: .seconds(15))
            scheduledAuto.remove(project.id)
            guard project.modelContext != nil, project.autoBackup else { return }
            await backUp(project, reason: .automatic)
        }
    }

    func showInFinder(_ project: Project) {
        let folder = folder(for: project)
        let target = FileManager.default.fileExists(atPath: folder.path) ? folder : BackupSettings.folder
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    nonisolated static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Project" : cleaned
    }
}

/// The file work, off the main actor.
nonisolated enum BackupWriter {
    static let prefix = "Backup "

    static func write(data: Data, summary: String, roots: [URL], skipIgnored: Bool,
                      into projectFolder: URL, keep: Int) throws -> BackupService.Outcome {
        let fm = FileManager.default
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let number = (existingNumbers(in: projectFolder).max() ?? 0) + 1
        // Write under a temporary name and rename at the end, so an interrupted backup never
        // looks like a finished one.
        let temp = projectFolder.appending(path: ".\(prefix)\(number) (in progress)", directoryHint: .isDirectory)
        try? fm.removeItem(at: temp)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)

        do {
            try data.write(to: temp.appending(path: "TwoToned Data.json"), options: .atomic)
            try summary.write(to: temp.appending(path: "TwoToned Summary.md"), atomically: true, encoding: .utf8)
            if !roots.isEmpty {
                let files = temp.appending(path: "Files", directoryHint: .isDirectory)
                try fm.createDirectory(at: files, withIntermediateDirectories: true)
                var usedNames: Set<String> = []
                for root in roots {
                    var name = root.lastPathComponent
                    var n = 2
                    while usedNames.contains(name) { name = "\(root.lastPathComponent) \(n)"; n += 1 }
                    usedNames.insert(name)
                    let target = files.appending(path: name, directoryHint: .isDirectory)
                    if skipIgnored {
                        try copyFolder(root, to: target)
                    } else {
                        try copyEverything(root, to: target)
                    }
                }
            }
            let final = projectFolder.appending(path: "\(prefix)\(number)", directoryHint: .isDirectory)
            try fm.moveItem(at: temp, to: final)
            prune(projectFolder, keep: keep)
            return .init(number: number, folder: final)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    static func existingNumbers(in folder: URL) -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            name.hasPrefix(prefix) ? Int(name.dropFirst(prefix.count)) : nil
        }
    }

    /// Deletes the oldest backups beyond `keep` (0 keeps everything).
    static func prune(_ folder: URL, keep: Int) {
        guard keep > 0 else { return }
        let numbers = existingNumbers(in: folder).sorted()
        for number in numbers.dropLast(keep) {
            try? FileManager.default.removeItem(at: folder.appending(path: "\(prefix)\(number)"))
        }
    }

    /// An exact copy of the whole folder (hidden files, .git, dependencies, symlinks as links).
    /// On the same disk APFS clones files, so this is near-instant and uses no extra local space.
    static func copyEverything(_ source: URL, to destination: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Copies a folder, skipping build/dependency folders and anything the root .gitignore excludes
    /// (the same rules the Files tab uses).
    static func copyFolder(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let ignore = GitIgnore(root: source)
        let rootPath = source.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants])
        else { return }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            var relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            let isDir = values?.isDirectory ?? false
            let name = url.lastPathComponent

            if isDir {
                if FolderScanner.ignoredDirectories.contains(name) || ignore.matches(relative, isDirectory: true) {
                    enumerator.skipDescendants()
                    continue
                }
                try fm.createDirectory(at: destination.appending(path: relative), withIntermediateDirectories: true)
                continue
            }
            if name == ".DS_Store" || ignore.matches(relative, isDirectory: false) { continue }
            let target = destination.appending(path: relative)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: url, to: target)
        }
    }
}
