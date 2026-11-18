import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings() }
            Tab("Claude Code", systemImage: "sparkle") { ClaudeSettings() }
            Tab("Backups", systemImage: "icloud.and.arrow.up") { BackupSettingsView() }
            Tab("Data", systemImage: "externaldrive") { DataSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 480)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.menuBarEnabled) private var menuBarEnabled = false
    @AppStorage(Prefs.menuBarLabelStyle) private var labelStyle = Prefs.LabelStyle.task.rawValue
    @AppStorage(Prefs.quickProjectID) private var projectID = ""
    @Query(sort: \Project.sortIndex) private var projects: [Project]

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $menuBarEnabled)
                Picker("Menu bar shows", selection: $labelStyle) {
                    ForEach(Prefs.LabelStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .disabled(!menuBarEnabled)
            } header: {
                Text("Menu bar")
            } footer: {
                Text("Check off your current task or add items from the menu bar without opening the full app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Project", selection: Binding(
                    get: { QuickProject.resolve(id: projectID, in: projects)?.id.uuidString ?? "" },
                    set: { projectID = $0 })) {
                    ForEach(projects, id: \.id) { Text($0.name).tag($0.id.uuidString) }
                }
                .disabled(projects.isEmpty)
            } header: {
                Text("Quick actions")
            } footer: {
                Text("The project the menu bar, quick add, and \u{201C}Complete current task\u{201D} act on. You can also switch it from the menu bar panel.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases.filter(\.isGlobal)) { row(for: $0) }
            } header: {
                Text("Work from any app")
            }
            Section {
                ForEach(ShortcutAction.allCases.filter { !$0.isGlobal }) { row(for: $0) }
            } header: {
                Text("In TwoToned Projects")
            } footer: {
                Text("Every shortcut starts unassigned. Shortcuts need ⌘, ⌥, or ⌃ so they never get in the way of typing.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(for action: ShortcutAction) -> some View {
        LabeledContent {
            ShortcutRecorder(action: action)
        } label: {
            Text(action.title)
            Text(action.detail)
        }
    }
}

private struct ClaudeSettings: View {
    private var connection: ClaudeConnection { .shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                HStack {
                    Spacer()
                    if connection.busy { ProgressView().controlSize(.small) }
                    if connection.status == .notConnected {
                        Button("Connect to Claude Code") { Task { await connection.connect() } }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.brandPurple)
                            .disabled(connection.busy)
                    } else {
                        if case .outdated = connection.status {
                            Button("Update connection") { Task { await connection.connect() } }
                                .disabled(connection.busy)
                        }
                        Button("Disconnect") { Task { await connection.disconnect() } }
                            .disabled(connection.busy)
                    }
                }
                if let message = connection.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("Adds TwoToned as a tool server in Claude Code's user settings, so every Claude Code session (including the Claude app's Code tab) can read and update your lists. Sessions that are already running pick it up when restarted.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("Claude only sees the project whose linked folder contains the folder the session works in. Other projects are never reachable.", systemImage: "lock")
                Label("Claude can add, edit, move, complete, reopen, and delete items, and manage lists. Its changes get a purple Claude badge and appear in each project's Activity tab.", systemImage: "sparkle")
                Label("Nothing is written to your project folders.", systemImage: "folder")
            } header: {
                Text("How it works")
            }
            .foregroundStyle(.secondary)

            Section("Details") {
                LabeledContent("Helper") {
                    Text(ClaudeConnection.helperPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { connection.refresh() }
    }

    private var statusText: String {
        switch connection.status {
        case .connected: "Connected"
        case .notConnected: "Not connected"
        case .outdated: "Points at another copy of the app"
        }
    }

    private var statusColor: Color {
        switch connection.status {
        case .connected: .green
        case .notConnected: .secondary
        case .outdated: .orange
        }
    }
}

private struct DataSettings: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @State private var message: String?
    @State private var confirmRemove = false
    @State private var removing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Backup") {
                    HStack {
                        Button("Export…") { message = FileTransfers.exportBackup(projects) }
                        Button("Import…") { message = FileTransfers.importBackup(into: context) }
                    }
                }
                Text("A backup is a single JSON file with every project, list, and item. Importing adds projects from the file and never overwrites ones you already have.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Data folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([DataStore.dataDirectory])
                    }
                }
            }
            if let message {
                Text(message).font(.callout)
            }

            Section {
                LabeledContent {
                    Button("Remove all data…", role: .destructive) { confirmRemove = true }
                } label: {
                    Text("Remove all TwoToned data")
                    Text("Use this before deleting the app so nothing is left behind.")
                }
            } header: {
                Text("Uninstall")
            }
        }
        .formStyle(.grouped)
        .disabled(removing)
        .alert("Remove all TwoToned data?", isPresented: $confirmRemove) {
            Button("Remove everything and quit", role: .destructive) {
                removing = true
                Task { await AppServices.current?.removeAllData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every project, list, and item, copied attachments, your settings and shortcuts, and the Claude Code connection, then quits. Your project folders aren't touched. Export a backup first if you might want your data back.")
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("StudioLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
            Text("TwoToned Projects")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .foregroundStyle(.secondary)
            Text("By TwoToned Studios")
                .foregroundStyle(Color.brandPurpleText)
            Link("www.twotonedstudios.com", destination: URL(string: "https://www.twotonedstudios.com")!)
                .foregroundStyle(Color.brandBlueText)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// Save/open panels for backups and Markdown export.
enum FileTransfers {
    static func exportBackup(_ projects: [Project]) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "TwoToned Projects Backup \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let ideas = (try? projects.first?.modelContext?.fetch(FetchDescriptor<BrainstormIdea>())) ?? []
            try Backup.encode(projects, brainstorm: ideas).write(to: url, options: .atomic)
            return "Exported \(projects.count) projects."
        } catch {
            return "Couldn't export the backup. \(error.localizedDescription)"
        }
    }

    static func importBackup(into context: ModelContext) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let summary = try Backup.restore(Data(contentsOf: url), into: context)
            var text = "Imported \(summary.imported) projects."
            if summary.skipped > 0 { text += " Skipped \(summary.skipped) you already have." }
            return text
        } catch {
            return "That file isn't a TwoToned Projects backup."
        }
    }

    static func exportMarkdown(_ project: Project) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(project.name).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MarkdownExport.markdown(for: project).write(to: url, atomically: true, encoding: .utf8)
    }
}
