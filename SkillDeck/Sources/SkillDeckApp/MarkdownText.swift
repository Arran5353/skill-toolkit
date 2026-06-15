import SwiftUI

/// A readable, styled Markdown renderer for skill/command usage bodies.
///
/// SwiftUI's `Text(AttributedString)` only renders *inline* markdown (bold, italic, code,
/// links) and collapses block structure. We parse the body into blocks (headings, lists,
/// fenced code, blockquotes, paragraphs) and render each with a distinct visual treatment —
/// accent-barred headings, colored list markers, code "cards", and tinted inline code — so
/// the usage reads like documentation rather than raw text.
struct MarkdownText: View {
    private let blocks: [Block]
    var accent: Color = .accentColor

    init(_ source: String, accent: Color = .accentColor) {
        self.blocks = MarkdownText.parse(source)
        self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if level <= 2 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 3, height: level == 1 ? 20 : 16)
                }
                inline(text)
                    .font(headingFont(level))
                    .fontWeight(level <= 2 ? .bold : .semibold)
                    .foregroundStyle(level <= 2 ? .primary : .secondary)
            }
            .padding(.top, level <= 2 ? 6 : 2)

        case .bullet(let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(accent.opacity(0.8))
                    .padding(.top, 6)
                inline(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 16)

        case .numbered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                inline(text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.5)).frame(width: 3)
                inline(text)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .paragraph(let text):
            inline(text)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let code, let lang):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red.opacity(0.55)).frame(width: 8, height: 8)
                    Circle().fill(Color.yellow.opacity(0.55)).frame(width: 8, height: 8)
                    Circle().fill(Color.green.opacity(0.55)).frame(width: 8, height: 8)
                    Spacer()
                    if let lang, !lang.isEmpty {
                        Text(lang.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05))

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    /// Renders inline markdown (bold/italic/code/links) within a single block. Inline code
    /// gets a tinted monospaced treatment via attribute inspection.
    private func inline(_ text: String) -> Text {
        guard var attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return Text(text)
        }
        // Tint inline-code runs so `code` reads as a pill-ish token.
        for run in attr.runs where run.inlinePresentationIntent == .code {
            attr[run.range].foregroundColor = accent
            attr[run.range].font = .system(.body, design: .monospaced)
        }
        return Text(attr)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(.title2, design: .rounded)
        case 2: return .system(.title3, design: .rounded)
        default: return .system(.headline, design: .rounded)
        }
    }

    // MARK: - Parsing

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String, depth: Int)
        case numbered(Int, String)
        case quote(String)
        case paragraph(String)
        case code(String, lang: String?)
    }

    private static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false
        var codeLang: String?

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }
        func flushCode() {
            blocks.append(.code(codeLines.joined(separator: "\n"), lang: codeLang))
            codeLines.removeAll()
            codeLang = nil
        }

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode { flushCode(); inCode = false }
                else {
                    flushParagraph()
                    inCode = true
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
                continue
            }
            if inCode { codeLines.append(line); continue }

            if trimmed.isEmpty { flushParagraph(); continue }

            if let h = heading(trimmed) {
                flushParagraph(); blocks.append(.heading(level: h.0, text: h.1)); continue
            }
            if let q = quoteText(trimmed) {
                flushParagraph(); blocks.append(.quote(q)); continue
            }
            if let num = numberedText(trimmed) {
                flushParagraph(); blocks.append(.numbered(num.0, num.1)); continue
            }
            if let b = bulletText(line) {
                flushParagraph(); blocks.append(.bullet(text: b.0, depth: b.1)); continue
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

    private static func quoteText(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func numberedText(_ line: String) -> (Int, String)? {
        // matches "1. text" / "12) text"
        var digits = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber { digits.append(line[idx]); idx = line.index(after: idx) }
        guard !digits.isEmpty, idx < line.endIndex, line[idx] == "." || line[idx] == ")" else { return nil }
        let rest = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, let n = Int(digits) else { return nil }
        return (n, rest)
    }

    private static func bulletText(_ rawLine: String) -> (String, Int)? {
        let leading = rawLine.prefix { $0 == " " || $0 == "\t" }
        let depth = min(leading.filter { $0 == " " }.count / 2 + leading.filter { $0 == "\t" }.count, 3)
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return (String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces), depth)
        }
        return nil
    }
}
