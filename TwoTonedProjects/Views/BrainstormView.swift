import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

/// A scratchpad for project ideas in bullet form. Each top-level bullet can have
/// sub-bullets, and any idea can be converted into a real project.
struct BrainstormView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BrainstormIdea.sortIndex) private var ideas: [BrainstormIdea]

    @State private var newIdea = ""
    @State private var converting: BrainstormIdea?
    @State private var deleting: BrainstormIdea?
    @FocusState private var focus: UUID?
    /// The idea being dragged (tracked here so hovering can reorder live).
    @State private var dragging: UUID?
    @State private var clickMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            addBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            if ideas.isEmpty {
                ContentUnavailableView {
                    Label("Brainstorm project ideas", systemImage: "lightbulb.max")
                } description: {
                    Text("Jot down an idea above, then add sub-bullets with more detail. When one is worth building, convert it into a project and every bullet lands in its Ideas list.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A plain stack (not a List): List rows guess their height when inserted
                // and don't re-measure growing text fields until you scroll, which clipped cards.
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(ideas) { idea in
                            IdeaCard(idea: idea, focus: $focus, isDragging: dragging == idea.id,
                                     onConvert: { converting = idea },
                                     onDelete: { deleting = idea })
                                .onDrag {
                                    dragging = idea.id
                                    return IdeaDrag.provider(for: idea.id)
                                }
                                .onDrop(of: [IdeaDrag.type], delegate: IdeaDropDelegate(
                                    target: idea.id, dragging: $dragging, reorder: reorder))
                        }
                        // Free space below the last idea: dropping here moves it to the end.
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .contentShape(Rectangle())
                            .onTapGesture { focus = nil }
                            .onDrop(of: [IdeaDrag.type], delegate: IdeaDropDelegate(
                                target: nil, dragging: $dragging, reorder: reorder))
                    }
                    .padding(.horizontal, 16)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { focus = nil }
                    }
                }
            }
        }
        // A drop anywhere else on the page still ends the drag cleanly.
        .onDrop(of: [IdeaDrag.type], isTargeted: nil) { _ in
            dragging = nil
            return true
        }
        .onAppear {
            // If a drag was cancelled outside the window, the next click clears its dimmed state.
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                dragging = nil
                // A click anywhere that isn't a text field ends editing, which also clears a blank
                // detail. (macOS doesn't do this on its own for clicks on empty space.)
                if !Self.isTextInput(at: event) {
                    DispatchQueue.main.async { focus = nil }
                }
                return event
            }
        }
        .onDisappear {
            for idea in ideas {
                idea.points.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            dragging = nil
        }
        .navigationTitle("Brainstorm")
        .sheet(item: $converting) { idea in
            NewProjectSheet(seedIdeas: idea.allIdeas, title: "Convert to project") { _ in
                context.delete(idea)
            }
        }
        .confirmationDialog("Delete this idea?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete idea", role: .destructive) {
                if let deleting { context.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("It and its sub-bullets are deleted. You can undo right after with Edit › Undo.")
        }
    }

    private var addBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: addIdea) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.brandPurple)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Add idea (or press Return)")
            .accessibilityLabel("Add idea")
            WrappingTextField(title: "New idea", text: $newIdea, lines: 1...6, onSubmit: addIdea)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func addIdea() {
        let text = newIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let idea = BrainstormIdea(text: text, sortIndex: (ideas.map(\.sortIndex).min() ?? 1) - 1)
        context.insert(idea)
        newIdea = ""
    }

    private static func isTextInput(at event: NSEvent) -> Bool {
        guard let window = event.window, let content = window.contentView else { return false }
        var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
        while let current = view {
            if current is NSText || current is NSTextField { return true }
            view = current.superview
        }
        return false
    }

    /// Moves the dragged idea to where `target` is (or to the end when `target` is nil).
    private func reorder(_ id: UUID, to target: UUID?) {
        guard id != target, let from = ideas.firstIndex(where: { $0.id == id }) else { return }
        var ordered = ideas
        let dragged = ordered.remove(at: from)
        if let target, let to = ideas.firstIndex(where: { $0.id == target }) {
            // Hovering a card below the dragged one puts it after that card; above puts it before.
            ordered.insert(dragged, at: to)
        } else {
            ordered.append(dragged)
        }
        guard ordered.map(\.id) != ideas.map(\.id) else { return }
        withAnimation(.snappy) {
            for (position, idea) in ordered.enumerated() where idea.sortIndex != position {
                idea.sortIndex = position
            }
        }
    }
}

/// Ideas are dragged as a private type so text fields inside the cards ignore them.
enum IdeaDrag {
    static let type = UTType(exportedAs: "com.twotonedstudios.projects.brainstorm-idea")

    static func provider(for id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

/// Reorders live while hovering, so you can see where the idea will land.
private struct IdeaDropDelegate: DropDelegate {
    let target: UUID?
    @Binding var dragging: UUID?
    let reorder: (UUID, UUID?) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) {
        guard let dragging else { return }
        reorder(dragging, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct IdeaCard: View {
    @Bindable var idea: BrainstormIdea
    var focus: FocusState<UUID?>.Binding
    var isDragging = false
    var onConvert: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Drag to reorder")
                Text("•").font(.title3.weight(.bold)).foregroundStyle(Color.brandPurpleText)
                WrappingTextField(title: "Idea", text: $idea.text, lines: 1...6) { addPoint(after: nil) }
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused(focus, equals: idea.id)
                Menu {
                    Button("Add sub-bullet") { addPoint(after: nil) }
                    Button("Convert to project…", action: onConvert)
                    Divider()
                    Button("Delete idea…", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Idea actions")
            }

            ForEach(idea.points) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("◦").foregroundStyle(.secondary)
                    // Bound by ID, not list position: a field that is still finishing its edit
                    // after its detail was removed must not write into another position (that crashed).
                    WrappingTextField(title: "Detail", text: pointText(point.id), lines: 1...6) { submitPoint(point.id) }
                        .textFieldStyle(.plain)
                        .focused(focus, equals: point.id)
                    Button {
                        removePoint(point.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                    .help("Remove this bullet")
                    .accessibilityLabel("Remove bullet")
                }
                .padding(.leading, 18)
            }

            HStack {
                Button {
                    addPoint(after: nil)
                } label: {
                    Label("Add detail", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.leading, 18)
                Spacer()
                Button("Convert to project…", action: onConvert)
                    .controlSize(.small)
            }
            .font(.callout)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isDragging ? 0.5 : 1)
        // A detail left blank disappears as soon as you click or tab away from it.
        .onChange(of: focus.wrappedValue) { old, new in
            guard let old, old != new else { return }
            removeIfEmpty(old)
        }
        // Clean up blank details left over from before this fix.
        .onAppear {
            idea.points.removeAll { isBlank($0) && $0.id != focus.wrappedValue }
        }
    }

    private func isBlank(_ point: BrainstormPoint) -> Bool {
        point.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func removeIfEmpty(_ id: UUID) {
        guard let point = idea.points.first(where: { $0.id == id }), isBlank(point) else { return }
        removePoint(id)
    }

    /// Removes a detail after the current event finishes, so its text field can end editing first.
    private func removePoint(_ id: UUID) {
        DispatchQueue.main.async {
            withAnimation(.snappy) { idea.points.removeAll { $0.id == id } }
        }
    }

    /// A binding to one detail's text that looks the detail up by ID every time.
    private func pointText(_ id: UUID) -> Binding<String> {
        Binding(
            get: { idea.points.first(where: { $0.id == id })?.text ?? "" },
            set: { newValue in
                guard let index = idea.points.firstIndex(where: { $0.id == id }) else { return }
                idea.points[index].text = newValue
            })
    }

    /// Return on a filled sub-bullet starts a new one below; Return on an empty one removes it.
    private func submitPoint(_ id: UUID) {
        guard let point = idea.points.first(where: { $0.id == id }) else { return }
        if isBlank(point) {
            focus.wrappedValue = nil
            removePoint(id)
        } else {
            addPoint(after: id)
        }
    }

    private func addPoint(after id: UUID?) {
        let point = BrainstormPoint(text: "")
        if let id, let index = idea.points.firstIndex(where: { $0.id == id }) {
            idea.points.insert(point, at: index + 1)
        } else {
            idea.points.append(point)
        }
        DispatchQueue.main.async { focus.wrappedValue = point.id }
    }
}
