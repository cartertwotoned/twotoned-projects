import Foundation

nonisolated struct IgnoredEntry: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let displayPath: String
    let isDirectory: Bool
}

nonisolated enum GitIgnoredResult: Sendable {
    case entries([IgnoredEntry])
    case notARepository
    case gitUnavailable
}

/// Asks git itself which files are ignored, so the answer matches git exactly
/// (nested .gitignore files, `!` exceptions, global excludes and all).
nonisolated enum GitIgnored {
    static func list(in roots: [URL]) -> GitIgnoredResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git"),
              FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools")
                || FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
        else { return .gitUnavailable }

        var entries: [IgnoredEntry] = []
        var anyRepo = false
        let multiple = roots.count > 1
        for root in roots {
            // Whole ignored folders are listed once (e.g. "node_modules/"), not file by file.
            guard let output = run(["-C", root.path, "ls-files", "--others", "--ignored", "--exclude-standard",
                                    "--directory", "--no-empty-directory"]) else { continue }
            anyRepo = true
            for line in output.split(separator: "\n") where !line.isEmpty {
                let relative = String(line)
                let isDirectory = relative.hasSuffix("/")
                let trimmed = isDirectory ? String(relative.dropLast()) : relative
                entries.append(IgnoredEntry(
                    url: root.appending(path: trimmed),
                    displayPath: multiple ? "\(root.lastPathComponent)/\(relative)" : relative,
                    isDirectory: isDirectory))
            }
        }
        guard anyRepo else { return .notARepository }
        return .entries(entries.sorted { $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending })
    }

    /// Runs git and returns stdout, or nil if it failed (e.g. not a repository).
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
