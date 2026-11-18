import Foundation
import UniformTypeIdentifiers

nonisolated enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case image, video, pdf, document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "Images"
        case .video: "Videos"
        case .pdf: "PDFs"
        case .document: "Docs"
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        }
    }

    static let documentExtensions: Set<String> = ["md", "markdown", "txt", "rtf", "rtfd", "doc", "docx", "pages"]

    static func of(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if documentExtensions.contains(ext) { return .document }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return nil
    }
}

nonisolated struct ScannedFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let relativePath: String
    let kind: FileKind
    let size: Int64
    let modified: Date
}

nonisolated struct LanguageCount: Identifiable, Hashable, Sendable {
    var id: String { language }
    let language: String
    let lines: Int
    let files: Int
}

nonisolated struct FolderScan: Sendable {
    var files: [ScannedFile] = []
    var fileCount = 0
    var totalSize: Int64 = 0
    var lastModified: Date?
    var lastModifiedPath: String?
    var languages: [LanguageCount] = []
    var scannedAt = Date()
    /// True if the scan hit its safety limits on a huge folder.
    var truncated = false

    var totalLines: Int { languages.reduce(0) { $0 + $1.lines } }
}

/// Walks linked folders off the main thread. Skips build and dependency folders and
/// anything the root `.gitignore` excludes.
nonisolated enum FolderScanner {
    static let ignoredDirectories: Set<String> = [
        "node_modules", ".git", "DerivedData", "build", "dist", ".build", "Pods", ".next", "target",
        "venv", ".venv", "__pycache__", ".svn", ".hg", ".idea", ".gradle", "Carthage", ".swiftpm",
        ".cache", ".turbo", ".parcel-cache", "coverage", ".nuxt", ".expo", "vendor", "bower_components",
    ]

    static let languages: [String: String] = [
        "swift": "Swift", "m": "Objective-C", "mm": "Objective-C", "h": "C/C++ header",
        "c": "C", "cc": "C++", "cpp": "C++", "cxx": "C++", "hpp": "C++",
        "js": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript",
        "ts": "TypeScript", "tsx": "TypeScript", "py": "Python", "rb": "Ruby", "go": "Go", "rs": "Rust",
        "java": "Java", "kt": "Kotlin", "kts": "Kotlin", "cs": "C#", "php": "PHP", "dart": "Dart",
        "lua": "Lua", "luau": "Luau", "gd": "GDScript", "html": "HTML", "htm": "HTML",
        "css": "CSS", "scss": "SCSS", "sass": "Sass", "less": "Less", "vue": "Vue", "svelte": "Svelte",
        "sh": "Shell", "zsh": "Shell", "bash": "Shell", "sql": "SQL", "r": "R", "scala": "Scala",
        "ex": "Elixir", "exs": "Elixir", "hs": "Haskell", "zig": "Zig", "glsl": "GLSL", "metal": "Metal",
        "astro": "Astro",
    ]

    static let maxFiles = 200_000
    static let maxListedFiles = 5_000
    static let maxLineCountBytes = 1_000_000

    static func scan(_ roots: [URL]) -> FolderScan {
        var result = FolderScan()
        var counts: [String: (lines: Int, files: Int)] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let multiple = roots.count > 1

        for root in roots {
            let scoped = root.startAccessingSecurityScopedResource()
            defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            let ignore = GitIgnore(root: root)
            let rootPath = root.standardizedFileURL.path
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }

            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let isDir = values?.isDirectory ?? false
                var relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
                if relative.hasPrefix("/") { relative.removeFirst() }

                if isDir {
                    if ignoredDirectories.contains(url.lastPathComponent) || ignore.matches(relative, isDirectory: true) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values?.isRegularFile ?? true, !ignore.matches(relative, isDirectory: false) else { continue }

                result.fileCount += 1
                if result.fileCount > maxFiles { result.truncated = true; break }
                let size = Int64(values?.fileSize ?? 0)
                let modified = values?.contentModificationDate ?? .distantPast
                result.totalSize += size
                if modified > (result.lastModified ?? .distantPast) {
                    result.lastModified = modified
                    result.lastModifiedPath = relative
                }

                if let language = languages[url.pathExtension.lowercased()] {
                    let lines = size <= maxLineCountBytes ? lineCount(of: url) : 0
                    counts[language, default: (0, 0)].lines += lines
                    counts[language, default: (0, 0)].files += 1
                }

                if let kind = FileKind.of(url) {
                    if result.files.count < maxListedFiles {
                        let shown = multiple ? "\(root.lastPathComponent)/\(relative)" : relative
                        result.files.append(ScannedFile(url: url, name: url.lastPathComponent, relativePath: shown,
                                                        kind: kind, size: size, modified: modified))
                    } else {
                        result.truncated = true
                    }
                }
            }
        }

        result.languages = counts
            .map { LanguageCount(language: $0.key, lines: $0.value.lines, files: $0.value.files) }
            .sorted { $0.lines > $1.lines }
        result.files.sort { $0.modified > $1.modified }
        result.scannedAt = .now
        return result
    }

    /// Counts newline bytes without decoding text.
    static func lineCount(of url: URL) -> Int {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else { return 0 }
        var lines = 0
        data.withUnsafeBytes { raw in
            for byte in raw where byte == 0x0A { lines += 1 }
        }
        if data.last != 0x0A { lines += 1 }
        return lines
    }
}

/// Minimal `.gitignore` support for the folder root: plain names, wildcards,
/// anchored paths and directory-only patterns. Negations (`!`) are ignored.
nonisolated struct GitIgnore: Sendable {
    private struct Rule: Sendable {
        let pattern: String
        let anchored: Bool
        let directoryOnly: Bool
    }

    private let rules: [Rule]

    init(root: URL) {
        guard let text = try? String(contentsOf: root.appending(path: ".gitignore"), encoding: .utf8) else {
            rules = []
            return
        }
        rules = text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("!") else { return nil }
            let directoryOnly = line.hasSuffix("/")
            if directoryOnly { line.removeLast() }
            if line.hasPrefix("**/") { line.removeFirst(3) }
            let anchored = line.contains("/")
            if line.hasPrefix("/") { line.removeFirst() }
            guard !line.isEmpty else { return nil }
            return Rule(pattern: line, anchored: anchored, directoryOnly: directoryOnly)
        }
    }

    func matches(_ relativePath: String, isDirectory: Bool) -> Bool {
        guard !rules.isEmpty else { return false }
        let name = (relativePath as NSString).lastPathComponent
        for rule in rules where !rule.directoryOnly || isDirectory {
            let target = rule.anchored ? relativePath : name
            if fnmatch(rule.pattern, target, rule.anchored ? FNM_PATHNAME : 0) == 0 { return true }
        }
        return false
    }
}
