import PortalKit
import SwiftUI

/// MarkdownView lays out an assistant answer. Blocks come from PortalKit's
/// splitter; the system renders the bold, italic, code and links inside them.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlocks.parse(MemoryCitation.linking(markdown)).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text))
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.callout.monospaced())
                    .padding(12)
            }
            .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                        Text(Self.inline(item))
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                        Text(Self.inline(item))
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle().fill(.secondary).frame(width: 3)
                Text(Self.inline(text)).foregroundStyle(.secondary)
            }
        case .rule:
            Divider()
        case .table(let headerCells, let columnAlignments, let bodyRows):
            MarkdownTableView(headerCells: headerCells, columnAlignments: columnAlignments, bodyRows: bodyRows)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        var result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Web addresses typed as plain text become links too, which the
        // app opens in its own browser. Code and existing links stay as they are.
        result = BareLinks.linked(result)
        result = styledLinks(result)
        return result
    }

    /// Text as it was written, whose web addresses are links.
    static func plain(_ text: String) -> AttributedString {
        styledLinks(BareLinks.linked(plainText: text))
    }

    /// Link text is small body text, where the accent is too faint on the
    /// page, so a link is underlined in the text color instead.
    static func styledLinks(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in result.runs where run.link != nil {
            result[run.range].underlineStyle = .single
            result[run.range].foregroundColor = Color.primary
        }
        return result
    }
}

/// MarkdownTableView is a table of an answer: a header row in semibold, thin
/// separators between rows, every other body row tinted, and each column
/// aligned as the Markdown says. The cells never wrap or truncate, so a table
/// wider than the bubble scrolls sideways, at any text size. The web draws
/// the same table with a rounded border and a tinted header.
private struct MarkdownTableView: View {
    let headerCells: [String]
    let columnAlignments: [MarkdownColumnAlignment]
    let bodyRows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headerCells.enumerated()), id: \.offset) { column, cell in
                        cellView(cell, column: column, isHeader: true)
                            .background(Color(.tertiarySystemFill))
                    }
                }
                ForEach(Array(bodyRows.enumerated()), id: \.offset) { rowIndex, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            cellView(cell, column: column, isHeader: false)
                                .background(rowIndex % 2 == 1 ? Color(.quaternarySystemFill) : Color.clear)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    private func cellView(_ text: String, column: Int, isHeader: Bool) -> some View {
        let alignment = column < columnAlignments.count ? columnAlignments[column] : .leading
        return Text(MarkdownView.inline(text))
            .font(isHeader ? .callout.weight(.semibold) : .callout)
            .fixedSize(horizontal: true, vertical: false)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    }
}

#Preview {
    ScrollView {
        MarkdownView(markdown: "# Title\n\nSome **bold** text and `code`.\n\n- one\n- two\n\n| Station | Picks |\n| --- | ---: |\n| One | 120 |\n\n```\nlet value = 1\n```")
            .padding()
    }
}
