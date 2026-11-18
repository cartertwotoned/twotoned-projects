import SwiftUI
import QuickLookThumbnailing
import QuickLook
import AppKit

enum FilesMode: Hashable {
    case all
    case kind(FileKind)
    case ignored
}

/// Gallery of images, videos, PDFs and docs from the project's linked folders,
/// plus a list of what git ignores.
struct FilesView: View {
    let project: Project

    private var store: FolderStore { .shared }
    @State private var mode: FilesMode = .all
    @State private var ignored: GitIgnoredResult?
    @State private var search = ""
    @State private var previewURL: URL?
    @State private var watcher: FolderWatcher?

    private var files: [ScannedFile] {
        let all = store.scan(for: project)?.files ?? []
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { file in
            (mode == .all || mode == .kind(file.kind)) && (query.isEmpty || file.relativePath.lowercased().contains(query))
        }
    }

    var body: some View {
        let files = files
        VStack(spacing: 0) {
            controls(count: files.count)
            Divider()
            if mode == .ignored {
                IgnoredList(result: ignored, search: search)
            } else if store.scan(for: project) == nil {
                ProgressView("Scanning folder…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(search.isEmpty ? "No files here" : "No matches",
                                       systemImage: "photo.on.rectangle",
                                       description: Text(search.isEmpty
                                           ? "Images, videos, PDFs, and docs in the linked folder show up here."
                                           : "Try a different search."))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 14)], spacing: 16) {
                        ForEach(files) { file in
                            FileTile(file: file)
                                .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
                                .onTapGesture { previewURL = file.url }
                                .contextMenu { menu(for: file) }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .quickLookPreview($previewURL, in: files.map(\.url))
        .onChange(of: mode) { _, new in if new == .ignored { loadIgnored() } }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func controls(count: Int) -> some View {
        HStack(spacing: 10) {
            Picker("Kind", selection: $mode) {
                Text("All").tag(FilesMode.all)
                ForEach(FileKind.allCases) { Text($0.title).tag(FilesMode.kind($0)) }
                Text("Git ignored").tag(FilesMode.ignored)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            TextField("Search files", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Spacer()

            if store.scan(for: project)?.truncated == true {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help("This folder is very large, so only the first 5,000 files are shown.")
            }
            if mode == .ignored {
                if case .entries(let list) = ignored {
                    Text("\(list.count) ignored").foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text("\(count) files").foregroundStyle(.secondary).monospacedDigit()
            }
            Button {
                store.refresh(project)
                if mode == .ignored { loadIgnored() }
            } label: {
                if store.isScanning(project) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Rescan folder")
            .accessibilityLabel("Rescan folder")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func menu(for file: ScannedFile) -> some View {
        Button("Quick Look") { previewURL = file.url }
        Button("Open") { NSWorkspace.shared.open(file.url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
        }
        if file.kind == .image {
            Divider()
            Button("Use as project icon") {
                if let data = try? Data(contentsOf: file.url) {
                    project.iconData = ImageTools.thumbnailPNG(from: data, maxPixel: 256)
                }
            }
        }
    }

    private func loadIgnored() {
        let roots = project.folders.map(\.url)
        Task {
            ignored = await Task.detached(priority: .utility) { GitIgnored.list(in: roots) }.value
        }
    }

    private func start() {
        store.refreshIfStale(project)
        // Watch only while this tab is visible.
        watcher = FolderWatcher(paths: project.folders.map(\.url.path)) { [project] in
            FolderStore.shared.refresh(project)
            if mode == .ignored { loadIgnored() }
        }
    }

    private func stop() {
        watcher?.stop()
        watcher = nil
    }
}

private struct FileTile: View {
    let file: ScannedFile

    var body: some View {
        VStack(spacing: 6) {
            Thumbnail(url: file.url, modified: file.modified, kind: file.kind)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
            VStack(spacing: 1) {
                Text(file.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .contentShape(Rectangle())
        .help(file.relativePath)
    }
}

/// Quick Look thumbnail, generated on demand and cached in memory.
struct Thumbnail: View {
    let url: URL
    let modified: Date
    let kind: FileKind

    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(4)
            } else {
                Image(systemName: kind.symbol)
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) { image = await ThumbnailCache.thumbnail(for: url, modified: modified, scale: scale) }
    }
}

@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        return c
    }()

    static func thumbnail(for url: URL, modified: Date, scale: CGFloat) async -> NSImage? {
        let key = "\(url.path)|\(modified.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 220, height: 220),
                                                   scale: scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct IgnoredList: View {
    let result: GitIgnoredResult?
    let search: String

    var body: some View {
        switch result {
        case nil:
            ProgressView("Asking git…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .gitUnavailable:
            ContentUnavailableView("Git isn't installed", systemImage: "exclamationmark.triangle",
                                   description: Text("Install Xcode or its command line tools to see ignored files."))
        case .notARepository:
            ContentUnavailableView("Not a git repository", systemImage: "arrow.triangle.branch",
                                   description: Text("The linked folder isn't tracked by git, so nothing is ignored."))
        case .entries(let all):
            let query = search.trimmingCharacters(in: .whitespaces).lowercased()
            let entries = query.isEmpty ? all : all.filter { $0.displayPath.lowercased().contains(query) }
            if entries.isEmpty {
                ContentUnavailableView(all.isEmpty ? "Nothing is ignored" : "No matches",
                                       systemImage: "eye",
                                       description: Text(all.isEmpty
                                           ? "Git isn't ignoring any files in this folder."
                                           : "Try a different search."))
            } else {
                List(entries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(entry.displayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if entry.isDirectory {
                            Text("Whole folder").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                        Button("Copy path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.url.path, forType: .string)
                        }
                    }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) {
                    Text("Listed by git, including nested .gitignore files and your global excludes. Ignored folders are shown once instead of file by file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
        }
    }
}
