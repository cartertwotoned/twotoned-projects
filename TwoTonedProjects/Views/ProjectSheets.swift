import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct NewProjectSheet: View {
    /// When converting a brainstorm, these lines go into the new project's Ideas list.
    var seedIdeas: [String] = []
    var title = "New project"
    /// Called after the project is created (e.g. to remove the brainstorm it came from).
    var onCreated: (Project) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(Navigator.self) private var nav

    @State private var name = ""
    @State private var status: ProjectStatus = .active
    @State private var colorHex = ProjectColors.swatches[0]
    @State private var folder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    StackedField("Name") {
                        WrappingTextField(title: "Name", text: $name, prompt: Text("Portfolio site"), lines: 1...3) {
                            if canCreate { create() }
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                    }
                    ColorSwatchPicker(hex: $colorHex)
                    LabeledContent("Folder") {
                        HStack(spacing: 6) {
                            if let folder {
                                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                                Button {
                                    self.folder = nil
                                } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Remove folder")
                            }
                            Button(folder == nil ? "Choose folder…" : "Change…") { chooseFolder() }
                        }
                    }
                } header: {
                    Text(title)
                } footer: {
                    Text(footer).foregroundStyle(.secondary)
                }

                if !seedIdeas.isEmpty {
                    Section("Goes into Ideas") {
                        ForEach(Array(seedIdeas.enumerated()), id: \.offset) { _, idea in
                            Label(idea, systemImage: "lightbulb")
                                .lineLimit(2)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create project") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .padding()
        }
        .frame(width: 460)
        .frame(maxHeight: 640)
    }

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var footer: String {
        var text = "New projects start with Bugs, Tasks, and Ideas lists. You can change them in project settings."
        if folder == nil { text += " Linking a folder is optional; you can do it later." }
        return text
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Link folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        // Helpful default for a plain new project; brainstorm conversions stay blank on purpose.
        if name.trimmingCharacters(in: .whitespaces).isEmpty, seedIdeas.isEmpty {
            name = url.lastPathComponent
        }
    }

    private func create() {
        guard canCreate else { return }
        let project = ProjectActions.createProject(
            named: name.trimmingCharacters(in: .whitespaces), status: status, in: context)
        project.colorHex = colorHex
        if let folder {
            project.folders = [FolderLink(url: folder, isPrimary: true)]
        }
        if let ideas = project.sortedLists.first(where: { !$0.includeInUpNext }) ?? project.sortedLists.last {
            for idea in seedIdeas {
                let item = Item(title: idea, list: ideas, project: project)
                context.insert(item)
                Ordering.place(item, in: project)
            }
        }
        onCreated(project)
        nav.selection = .project(project.id)
        dismiss()
    }
}

struct ColorSwatchPicker: View {
    @Binding var hex: String

    var body: some View {
        LabeledContent("Color") {
            HStack(spacing: 6) {
                ForEach(ProjectColors.swatches, id: \.self) { swatch in
                    Button {
                        hex = swatch
                    } label: {
                        Circle()
                            .fill(Color(hex: swatch) ?? .gray)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if swatch.caseInsensitiveCompare(hex) == .orderedSame {
                                    Circle().strokeBorder(.primary, lineWidth: 2).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(swatch)")
                }
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(hex: hex) ?? .gray },
                    set: { hex = $0.hexString ?? hex }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}

struct ProjectSettingsSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var listToDelete: TaskList?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Project") {
                    StackedField("Name") {
                        WrappingTextField(title: "Name", text: $project.name, prompt: Text("Project name"), lines: 1...3)
                    }
                    Picker("Status", selection: Binding(get: { project.status }, set: { project.status = $0 })) {
                        ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                    }
                    ColorSwatchPicker(hex: Binding(
                        get: { project.colorHex ?? ProjectColors.swatches[0] },
                        set: { project.colorHex = $0 }))
                    LabeledContent("Icon") {
                        HStack {
                            ProjectIconView(project: project, size: 32)
                            Button("Choose image…") { chooseIcon() }
                            if project.iconData != nil {
                                Button("Remove") { project.iconData = nil }
                            }
                        }
                    }
                    StackedField("GitHub repo") {
                        TextField("GitHub repo", text: $project.githubURL, prompt: Text("https://github.com/you/repo"))
                    }
                    StackedField("Description") {
                        TextField("Description", text: $project.summary, prompt: Text("What this project is"), axis: .vertical)
                            .lineLimit(2...5)
                    }
                }

                Section {
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
                            if !folder.isPrimary, project.folders.count > 1 {
                                Button("Make primary") { makePrimary(folder) }
                                    .buttonStyle(.link)
                            }
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                            } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help("Show in Finder")
                            Button(role: .destructive) {
                                removeFolder(folder)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Unlink folder (nothing on disk changes)")
                        }
                    }
                    Button {
                        addFolder()
                    } label: {
                        Label("Link folder…", systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("Folders")
                } footer: {
                    Text("TwoToned only reads linked folders; it never writes to them. The primary folder supplies the README and is the one Claude Code sessions match on.")
                        .foregroundStyle(.secondary)
                }

                ProjectBackupSection(project: project)

                Section {
                    ForEach(project.sortedLists, id: \.id) { list in
                        ListSettingsRow(list: list, project: project) { listToDelete = list }
                    }
                    .onMove(perform: moveLists)
                    Button {
                        ProjectActions.addList(named: "New list", to: project, context: context)
                    } label: {
                        Label("Add list", systemImage: "plus")
                    }
                } header: {
                    Text("Lists")
                } footer: {
                    Text("Drag to reorder. Lists higher up win ties in Up Next, so keep Bugs at the top if bugs should come first.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560)
        .frame(minHeight: 380, idealHeight: 700, maxHeight: 820)
        .confirmationDialog(
            "Delete the \u{201C}\(listToDelete?.name ?? "")\u{201D} list?",
            isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } })
        ) {
            Button("Delete list and its items", role: .destructive) {
                if let listToDelete { context.delete(listToDelete) }
                listToDelete = nil
            }
        } message: {
            Text("\(listToDelete?.items?.count ?? 0) items in this list, including completed ones, will be deleted. To keep them, move them to another list first.")
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Link folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        guard !project.folders.contains(where: { $0.path == path }) else { return }
        project.folders.append(FolderLink(url: url, isPrimary: project.folders.isEmpty))
        FolderStore.shared.refresh(project)
    }

    private func removeFolder(_ folder: FolderLink) {
        project.folders.removeAll { $0.id == folder.id }
        if !project.folders.isEmpty, !project.folders.contains(where: \.isPrimary) {
            project.folders[0].isPrimary = true
        }
        FolderStore.shared.refresh(project)
    }

    private func makePrimary(_ folder: FolderLink) {
        for index in project.folders.indices {
            project.folders[index].isPrimary = project.folders[index].id == folder.id
        }
    }

    /// Picks an icon image, starting in the project's folder when it has one.
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.directoryURL = project.primaryFolder?.url
        panel.prompt = "Use as icon"
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        project.iconData = ImageTools.thumbnailPNG(from: data, maxPixel: 256)
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
        var lists = project.sortedLists
        lists.move(fromOffsets: source, toOffset: destination)
        for (index, list) in lists.enumerated() { list.sortIndex = index }
    }
}

private struct ListSettingsRow: View {
    @Bindable var list: TaskList
    let project: Project
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(TaskList.symbolChoices, id: \.self) { symbol in
                    Button { list.symbol = symbol } label: { Label(symbol, systemImage: symbol) }
                }
            } label: {
                Image(systemName: list.symbol)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Change icon")

            WrappingTextField(title: "List name", text: $list.name, lines: 1...2)
                .labelsHidden()

            Toggle("Up Next", isOn: $list.includeInUpNext)
                .toggleStyle(.checkbox)
                .help("Include this list's open items in Up Next")
            Toggle("Bug fields", isOn: $list.isBugList)
                .toggleStyle(.checkbox)
                .help("New items in this list show bug detail fields")
            Button {
                ProjectActions.setDefault(list, in: project)
            } label: {
                Image(systemName: list.isDefault ? "star.fill" : "star")
                    .foregroundStyle(list.isDefault ? Color.brandBlue : .secondary)
            }
            .buttonStyle(.borderless)
            .help(list.isDefault ? "Default list for new items" : "Make this the default list for new items")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled((project.lists?.count ?? 0) <= 1)
            .help("Delete list")
        }
    }
}

/// A form field with its label above it. Forms on macOS right-align a field's text when the
/// label sits beside it, which hides a trailing space until the next character is typed.
private struct StackedField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    init(_ label: String, @ViewBuilder field: () -> Field) {
        self.label = label
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            field
                .labelsHidden()
                .multilineTextAlignment(.leading)
        }
    }
}
