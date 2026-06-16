import SwiftUI
import SkillDeckCore

/// A readable, styled Markdown renderer for skill/command usage bodies.
///
/// SwiftUI's `Text(AttributedString)` only renders *inline* markdown (bold, italic, code,
/// links) and collapses block structure. We parse the body into blocks (headings, lists,
/// fenced code, blockquotes, paragraphs) and render each with a distinct visual treatment —
/// accent-barred headings, colored list markers, code "cards", and tinted inline code — so
/// the usage reads like documentation rather than raw text.
///
/// Parsing is delegated to `MarkdownParser` in SkillDeckCore so it can be unit-tested.
struct MarkdownText: View {
    private let blocks: [MarkdownBlock]
    var accent: Color = .accentColor

    init(_ source: String, accent: Color = .accentColor) {
        self.blocks = MarkdownParser.parse(source)
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
    private func view(for block: MarkdownBlock) -> some View {
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

        case .code(let code, let language):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red.opacity(0.55)).frame(width: 8, height: 8)
                    Circle().fill(Color.yellow.opacity(0.55)).frame(width: 8, height: 8)
                    Circle().fill(Color.green.opacity(0.55)).frame(width: 8, height: 8)
                    Spacer()
                    if let lang = language, !lang.isEmpty {
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

        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                        Text(h)
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}
