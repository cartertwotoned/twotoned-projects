import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import QuickLook

struct ItemInspector: View {
    @Bindable var item: Item
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var newTag = ""
    @State private var newSubtask = ""
    @State private var newLink = ""
    @State private var previewNotes = false
    @State private var confirmDelete = false
    @State private var importingScreenshot = false
    @State private var previewURL: URL?

    var body: some View {
        Form {
            Section {
                WrappingTextField(title: "Title", text: bind(\.title), prompt: Text("Title"), lines: 1...6)
                    .font(.headline)
                    .labelsHidden()

                if let project = item.project {
                    Picker("List", selection: listBinding(project)) {
                        ForEach(project.sortedLists, id: \.id) { list in
                            Label(list.name, systemImage: list.symbol).tag(Optional(list.id))
                        }
                    }
                }

                Picker("Priority", selection: bind(\.priorityRaw)) {
                    ForEach(Priority.allCases.reversed()) { Text($0.title).tag($0.rawValue) }
                }

                Toggle("Due date", isOn: Binding(
                    get: { item.dueDate != nil },
                    set: { on in
                        item.dueDate = on ? Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)) : nil
                        item.touch()
                    }))
                if item.dueDate != nil {
                    DatePicker("Due", selection: Binding(
                        get: { item.dueDate ?? .now },
                        set: { item.dueDate = $0; item.touch() }), displayedComponents: .date)
                }
            }

            Section("Tags") {
                if !item.tags.isEmpty {
                    FlowLayout {
                        ForEach(item.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                Button {
                                    item.tags.removeAll { $0 == tag }
                                    item.touch()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Remove \(tag)")
                            }
                            .font(.callout)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
                WrappingTextField(title: "Add tag", text: $newTag, prompt: Text("Add tag"), lines: 1...2) {
                        let tag = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                        if !tag.isEmpty, !item.tags.contains(tag) { item.tags.append(tag); item.touch() }
                        newTag = ""
                    }
                    .labelsHidden()
            }

            Section {
                if previewNotes {
                    if item.notes.isEmpty {
                        Text("No notes").foregroundStyle(.secondary)
                    } else {
                        MarkdownView(text: item.notes)
                    }
                } else {
                    TextEditor(text: bind(\.notes))
                        .font(.body)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                }
            } header: {
                HStack {
                    Text("Notes")
                    Spacer()
                    Picker("Notes mode", selection: $previewNotes) {
                        Text("Edit").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Section("Subtasks") {
                ForEach($item.subtasks) { $sub in
                    HStack {
                        Toggle("Done", isOn: Binding(get: { sub.isDone }, set: { sub.isDone = $0; item.touch() }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        WrappingTextField(title: "Subtask", text: $sub.title, prompt: Text("Subtask"), lines: 1...4)
                            .labelsHidden()
                            .strikethrough(sub.isDone)
                            .foregroundStyle(sub.isDone ? .secondary : .primary)
                        Button {
                            item.subtasks.removeAll { $0.id == sub.id }
                            item.touch()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove subtask")
                    }
                }
                .onMove { item.subtasks.move(fromOffsets: $0, toOffset: $1); item.touch() }
                WrappingTextField(title: "Add subtask", text: $newSubtask, prompt: Text("Add subtask"), lines: 1...4) {
                        let title = newSubtask.trimmingCharacters(in: .whitespaces)
                        if !title.isEmpty { item.subtasks.append(Subtask(title: title)); item.touch() }
                        newSubtask = ""
                    }
                    .labelsHidden()
            }

            Section("Links") {
                ForEach(item.links, id: \.self) { link in
                    HStack {
                        if let url = URL(string: link), url.scheme != nil {
                            Link(link, destination: url).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text(link).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            item.links.removeAll { $0 == link }
                            item.touch()
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove link")
                    }
                }
                WrappingTextField(title: "Add link", text: $newLink, prompt: Text("Add link"), lines: 1...3) {
                        var link = newLink.trimmingCharacters(in: .whitespaces)
                        if !link.isEmpty, !link.contains("://") { link = "https://" + link }
                        if !link.isEmpty, !item.links.contains(link) { item.links.append(link); item.touch() }
                        newLink = ""
                    }
                    .labelsHidden()
            }

            Section("Attachments") {
                ForEach(item.attachments) { attachment in
                    AttachmentRow(attachment: attachment) {
                        previewURL = attachment.url
                    } onRemove: {
                        withAnimation { Attachments.remove(attachment, from: item) }
                    }
                }
                Button {
                    chooseAttachments()
                } label: {
                    Label("Attach file…", systemImage: "paperclip")
                }
                .buttonStyle(.borderless)
            }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                files.forEach { Attachments.add($0, to: item) }
                return !files.isEmpty
            }

            if item.showsBugDetails {
                bugSection
            } else {
                Section {
                    Button("Add bug details") { item.showsBugDetails = true }
                        .buttonStyle(.link)
                }
            }

            Section("Info") {
                LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                if let completed = item.completedAt {
                    LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Added by") {
                    if item.createdBy == .claude { ClaudeBadge() } else { Text("You") }
                }
                if item.lastModifiedBy == .claude {
                    LabeledContent("Last changed by") { ClaudeBadge() }
                }
            }

            Section {
                HStack {
                    Button(item.isCompleted ? "Reopen" : "Mark complete") {
                        withAnimation { ProjectActions.toggleComplete(item) }
                    }
                    Spacer()
                    Button("Delete item…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete \u{201C}\(item.title)\u{201D}?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                onDelete()
                ProjectActions.delete(item, context: context)
            }
        } message: {
            Text("You can undo right after with Edit › Undo.")
        }
        .quickLookPreview($previewURL, in: item.attachments.map(\.url))
        .fileImporter(isPresented: $importingScreenshot, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { loadScreenshot(from: url) }
        }
    }

    private var bugSection: some View {
        Section {
            LabeledTextEditor(title: "Steps to reproduce", text: bind(\.stepsToReproduce))
            LabeledTextEditor(title: "Expected behavior", text: bind(\.expectedBehavior))
            LabeledTextEditor(title: "Actual behavior", text: bind(\.actualBehavior))
            VStack(alignment: .leading, spacing: 6) {
                Text("Screenshot").foregroundStyle(.secondary)
                if let data = item.screenshotData, let image = ImageCache.image(for: data, key: "shot-\(item.id)") {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button("Replace…") { importingScreenshot = true }
                        Button("Remove", role: .destructive) { item.screenshotData = nil; item.touch() }
                    }
                } else {
                    Button { importingScreenshot = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus").font(.title2)
                            Text("Choose or drop an image")
                        }
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .foregroundStyle(.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.quaternary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                loadScreenshot(from: url)
                return true
            }
        } header: {
            HStack {
                Text("Bug details")
                Spacer()
                Button("Hide") { item.showsBugDetails = false }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Hides the bug fields. Anything you entered is kept.")
            }
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = item.project?.primaryFolder?.url
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { Attachments.add($0, to: item) }
    }

    private func loadScreenshot(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        // Cap stored screenshots at 2400px so the database stays small.
        item.screenshotData = ImageTools.thumbnailPNG(from: data, maxPixel: 2400) ?? data
        item.touch()
    }

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<Item, T>) -> Binding<T> {
        Binding(
            get: { item[keyPath: keyPath] },
            set: { item[keyPath: keyPath] = $0; item.touch() })
    }

    private func listBinding(_ project: Project) -> Binding<UUID?> {
        Binding(
            get: { item.list?.id },
            set: { id in
                if let list = project.sortedLists.first(where: { $0.id == id }) {
                    withAnimation { ProjectActions.move(item, to: list) }
                }
            })
    }

    private func markdown(_ text: String) -> AttributedString {
        if text.isEmpty { return AttributedString("No notes") }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: 50)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct AttachmentRow: View {
    let attachment: Attachment
    var onOpen: () -> Void
    var onRemove: () -> Void

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: attachment.url.path)
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name).lineLimit(1).truncationMode(.middle)
                if !exists {
                    Text("File not found").font(.caption).foregroundStyle(.red)
                } else if attachment.isStoredCopy {
                    Text("Copy stored in TwoToned").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onRemove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove attachment")
                .accessibilityLabel("Remove attachment")
        }
        .contentShape(Rectangle())
        .onTapGesture { if exists { onOpen() } }
        .contextMenu {
            Button("Quick Look", action: onOpen).disabled(!exists)
            Button("Open") { NSWorkspace.shared.open(attachment.url) }.disabled(!exists)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([attachment.url]) }.disabled(!exists)
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}
