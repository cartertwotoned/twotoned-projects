import SwiftUI

struct ProjectIconView: View {
    let project: Project
    var size: CGFloat = 18

    var body: some View {
        // The project color always sits behind the icon, so transparent images
        // stay readable against any background (including sidebar selection).
        ZStack {
            Color(hex: project.colorHex) ?? ProjectColors.fallback
            if let data = project.iconData, let image = ImageCache.image(for: data, key: project.id.uuidString) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(project.name.first.map { String($0).uppercased() } ?? "?")
                    .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// Small rounded label used for list names, tags, etc.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Purple badge marking items Claude created or changed.
struct ClaudeBadge: View {
    var body: some View {
        Chip(text: "Claude", symbol: "sparkle", tint: .brandPurpleText)
            .help("Added or changed by Claude Code")
    }
}

/// Simple wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

extension Date {
    var relativeDueText: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInTomorrow(self) { return "Tomorrow" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A single-line text value that wraps onto more lines instead of scrolling sideways,
/// so the text cursor and the last characters you typed always stay visible.
/// Return still submits; it never inserts a line break.
struct WrappingTextField: View {
    let title: String
    @Binding var text: String
    var prompt: Text?
    var lines: ClosedRange<Int> = 1...4
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(title, text: $text, prompt: prompt, axis: .vertical)
            .lineLimit(lines)
            // Forms right-align text by default, which hides a trailing space until the
            // next character is typed. Leading alignment keeps every keystroke visible.
            .multilineTextAlignment(.leading)
            .onSubmit(onSubmit)
            .onChange(of: text) { _, new in
                // Some text fields insert a line break on Return or paste; treat it as submit.
                guard new.contains(where: \.isNewline) else { return }
                text = new.split(whereSeparator: \.isNewline).joined(separator: " ")
                onSubmit()
            }
    }
}
