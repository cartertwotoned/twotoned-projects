import SwiftUI

/// Lightweight Markdown renderer for READMEs and notes: headings, paragraphs,
/// bullet/numbered lists, quotes, code blocks, rules, and inline styling/links.
struct MarkdownView: View {
    let text: String

    private enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String, indent: Int)
        case numbered(String, String, indent: Int)
        case quote(String)
        case code(String)
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(inline(text))
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .numbered(let number, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text))
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            Text(inline(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(.callout, design: .monospaced))
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in text.components(separatedBy: .newlines) {
            if var lines = code {
                if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    lines.append(raw)
                    code = lines
                }
                continue
            }
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = (raw.prefix { $0 == " " }.count) / 2

            if line.hasPrefix("```") { flush(); code = []; continue }
            if line.isEmpty { flush(); continue }
            // Skip HTML and image-only lines (badges, logos) common in READMEs.
            if line.hasPrefix("<") || line.hasPrefix("![") || line.hasPrefix("[![") { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                blocks.append(.heading(min(level, 4), line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
            } else if ["---", "***", "___"].contains(line) {
                flush(); blocks.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush(); blocks.append(.bullet(String(line.dropFirst(2)), indent: indent))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.numbered(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...]), indent: indent))
            } else if line.hasPrefix(">") {
                flush(); blocks.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
