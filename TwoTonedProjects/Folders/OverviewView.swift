import SwiftUI
import AppKit

/// README, folder stats, and quick "open in" buttons for the linked folders.
struct OverviewView: View {
    let project: Project

    private var store: FolderStore { .shared }
    @State private var readme: (name: String, text: String)?
    @State private var readmeLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                foldersCard
                statsCard
                readmeCard
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { store.refreshIfStale(project) }
        .task(id: project.primaryFolder?.path) { await loadReadme() }
    }

    // MARK: Folders

    private var foldersCard: some View {
        Card(title: "Folders", symbol: "folder") {
            ForEach(project.folders) { folder in
                HStack(spacing: 8) {
                    Image(systemName: folder.isPrimary ? "folder.fill" : "folder")
                        .foregroundStyle(folder.isPrimary ? Color.brandBlue : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.name)
                        Text(folder.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    OpenInButtons(folder: folder.url)
                }
            }
        }
    }

    // MARK: Stats

    private var statsCard: some View {
        Card(title: "Stats", symbol: "chart.bar") {
            if let scan = store.scan(for: project) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                    GridRow {
                        Stat(label: "Files", value: scan.fileCount.formatted())
                        Stat(label: "Folder size", value: ByteCountFormatter.string(fromByteCount: scan.totalSize, countStyle: .file))
                        Stat(label: "Lines of code", value: scan.totalLines.formatted())
                        Stat(label: "Last modified", value: scan.lastModified?.formatted(.relative(presentation: .named)) ?? "–")
                    }
                }
                if let path = scan.lastModifiedPath {
                    Text("Most recent change: \(path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !scan.languages.isEmpty {
                    Divider()
                    LanguageBars(languages: Array(scan.languages.prefix(8)), total: max(scan.totalLines, 1))
                }
                HStack {
                    Text("Skips build and dependency folders and anything in .gitignore. Scanned \(scan.scannedAt.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Rescan") { store.refresh(project) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(store.isScanning(project))
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning folder…").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: README

    @ViewBuilder
    private var readmeCard: some View {
        if let readme {
            Card(title: readme.name, symbol: "book") {
                MarkdownView(text: readme.text)
            }
        } else if readmeLoaded {
            Card(title: "README", symbol: "book") {
                Text("No README in \(project.primaryFolder?.name ?? "the folder").")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadReadme() async {
        guard let folder = project.primaryFolder?.url else { readme = nil; readmeLoaded = true; return }
        let result: (String, String)? = await Task.detached(priority: .utility) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let candidates = names.filter { $0.lowercased().hasPrefix("readme") }
                .sorted { a, b in a.lowercased().hasSuffix(".md") && !b.lowercased().hasSuffix(".md") }
            guard let name = candidates.first,
                  let text = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) else { return nil }
            return (name, String(text.prefix(200_000)))
        }.value
        readme = result.map { (name: $0.0, text: $0.1) }
        readmeLoaded = true
    }
}

private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct LanguageBars: View {
    let languages: [LanguageCount]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(languages.enumerated()), id: \.element.id) { index, lang in
                HStack(spacing: 10) {
                    Text(lang.language)
                        .frame(width: 110, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        Capsule()
                            .fill(index.isMultiple(of: 2) ? Color.brandBlue : Color.brandPurple)
                            .frame(width: max(3, geo.size.width * Double(lang.lines) / Double(total)))
                    }
                    .frame(height: 8)
                    Text("\(lang.lines.formatted()) lines")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 110, alignment: .trailing)
                }
                .font(.callout)
            }
        }
    }
}

/// Finder / Terminal / VS Code / Xcode buttons (only for apps that are installed).
struct OpenInButtons: View {
    let folder: URL

    private static let apps: [(name: String, bundleID: String, symbol: String)] = [
        ("Finder", "com.apple.finder", "folder"),
        ("Terminal", "com.apple.Terminal", "terminal"),
        ("VS Code", "com.microsoft.VSCode", "chevron.left.forwardslash.chevron.right"),
        ("Xcode", "com.apple.dt.Xcode", "hammer"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.apps, id: \.bundleID) { app in
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                    Button {
                        open(with: app.bundleID, appURL: appURL)
                    } label: {
                        Image(systemName: app.symbol)
                    }
                    .buttonStyle(.borderless)
                    .help("Open in \(app.name)")
                    .accessibilityLabel("Open in \(app.name)")
                }
            }
        }
    }

    private func open(with bundleID: String, appURL: URL) {
        if bundleID == "com.apple.finder" {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
