import SwiftUI

/// Lightweight Markdown renderer for skill/command usage bodies.
///
/// SwiftUI's `Text(AttributedString)` only renders *inline* markdown (bold, italic, code,
/// links) and collapses block structure. To make usage text readable we split the body into
/// blocks (headings, list items, fenced code, paragraphs) and style each block, applying
/// inline markdown within non-code blocks via `AttributedString(markdown:)`.
struct MarkdownText: View {
    private let blocks: [Block]

    init(_ source: String) {
        self.blocks = MarkdownText.parse(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
        case .paragraph(let text):
            inline(text)
        case .code(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Renders inline markdown (bold/italic/code/links) within a single block.
    private func inline(_ text: String) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }

    // MARK: - Parsing

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
        case code(String)
    }

    private static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }
        func flushCode() {
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll()
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode { flushCode(); inCode = false }
                else { flushParagraph(); inCode = true }
                continue
            }
            if inCode { codeLines.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if let h = heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: h.0, text: h.1))
                continue
            }
            if let bullet = bulletText(trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                continue
            }
            paragraph.append(trimmed)
        }
        if inCode { flushCode() } else { flushParagraph() }
        return blocks
    }

    private static func heading(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1; idx = line.index(after: idx)
        }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
