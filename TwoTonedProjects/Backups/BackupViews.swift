import SwiftUI
import AppKit

/// Toolbar button: back up the project now (spinner while running).
struct BackupButton: View {
    let project: Project
    private var service: BackupService { .shared }

    var body: some View {
        Button {
            Task { await service.backUp(project) }
        } label: {
            if service.isRunning(project) {
                ProgressView().controlSize(.small)
            } else {
                Label("Back up now", systemImage: "icloud.and.arrow.up")
            }
        }
        .disabled(service.isRunning(project))
        .help(helpText)
    }

    private var helpText: String {
        guard let last = project.lastBackupAt else { return "Back up now (never backed up)" }
        return "Back up now (last backup \(last.formatted(.relative(presentation: .named))))"
    }
}

/// Project settings section: last backup, back up now, automatic backups.
struct ProjectBackupSection: View {
    @Bindable var project: Project
    private var service: BackupService { .shared }

    var body: some View {
        Section {
            LabeledContent("Last backup") {
                HStack(spacing: 8) {
                    if service.isRunning(project) {
                        ProgressView().controlSize(.small)
                        Text("Backing up…").foregroundStyle(.secondary)
                    } else {
                        Text(project.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Back up now") { Task { await service.backUp(project) } }
                    .disabled(service.isRunning(project))
                Button("Show in Finder") { service.showInFinder(project) }
            }
            Toggle("Back up automatically when items are completed", isOn: $project.autoBackup)
            if project.autoBackup {
                Stepper(value: $project.autoBackupMinutes, in: 5...240, step: 5) {
                    LabeledContent("At most every", value: "\(project.autoBackupMinutes) minutes")
                }
            }
        } header: {
            Text("Backups")
        } footer: {
            Text("Backups go to \(BackupSettings.displayPath) as Backup 1, Backup 2, and so on. Change the folder and how many to keep in Settings › Backups.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Settings › Backups.
struct BackupSettingsView: View {
    @AppStorage(BackupSettings.folderKey) private var folderPath = ""
    @AppStorage(BackupSettings.maxCountKey) private var maxCount = BackupSettings.defaultMaxCount
    @AppStorage(BackupSettings.contentsKey) private var contents = BackupContents.everything.rawValue

    var body: some View {
        Form {
            Section {
                LabeledContent("Backup folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(BackupSettings.displayPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing)
                        HStack {
                            Button("Choose…", action: chooseFolder)
                            Button("Show in Finder") {
                                try? FileManager.default.createDirectory(at: BackupSettings.folder, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([BackupSettings.folder])
                            }
                            if !folderPath.isEmpty {
                                Button("Use default") { folderPath = "" }
                            }
                        }
                    }
                }
                if BackupSettings.iCloudDrive == nil {
                    Label("iCloud Drive isn't turned on, so backups stay on this Mac. Turn on iCloud Drive in System Settings, or choose another folder.",
                          systemImage: "exclamationmark.icloud")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if !BackupSettings.isInICloud {
                    Label("This folder isn't in iCloud Drive, so backups won't upload.", systemImage: "icloud.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Where")
            } footer: {
                Text("Each project gets its own folder, created on its first backup, with numbered backups inside: the highest number is the newest.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Folder files", selection: $contents) {
                    ForEach(BackupContents.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                Text((BackupContents(rawValue: contents) ?? .everything).detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What")
            } footer: {
                Text("Every backup also includes the project's TwoToned data (TwoToned Data.json, to import in Settings › Data) and a readable summary.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep every backup", isOn: Binding(
                    get: { maxCount == 0 },
                    set: { maxCount = $0 ? 0 : BackupSettings.defaultMaxCount }))
                if maxCount > 0 {
                    Stepper(value: $maxCount, in: 1...100) {
                        LabeledContent("Keep up to", value: "\(maxCount) per project")
                    }
                }
            } header: {
                Text("How many")
            } footer: {
                Text(maxCount > 0
                     ? "When a new backup goes past the limit, the oldest one for that project is deleted."
                     : "Old backups are never deleted. They can add up in iCloud storage.")
                    .foregroundStyle(.secondary)
            }

            Section("Restoring") {
                Text("Copy files back from a backup's Files folder in Finder. To restore a project's lists, import its TwoToned Data.json in Settings › Data. That adds the project if it isn't already in the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = BackupSettings.iCloudDrive
        panel.prompt = "Use for backups"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
    }
}
