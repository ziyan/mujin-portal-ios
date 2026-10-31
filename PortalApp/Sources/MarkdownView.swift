import PortalKit
import SwiftUI

/// MarkdownView lays out an assistant answer. Blocks come from PortalKit's
/// splitter; the system renders the bold, italic, code and links inside them.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
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
        }
    }

    static func inline(_ text: String) -> AttributedString {
        var result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Web addresses typed as plain text become links too, which the
        // app opens in its own browser.
        let plain = String(result.characters)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for match in detector?.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) ?? [] {
            guard let url = match.url, let range = Range(match.range, in: plain), let start = AttributedString.Index(range.lowerBound, within: result),
                let end = AttributedString.Index(range.upperBound, within: result), result[start..<end].link == nil
            else { continue }
            result[start..<end].link = url
        }
        // Link text is small body text, where the accent is too faint on the
        // page, so a link is underlined in the text color instead.
        for run in result.runs where run.link != nil {
            result[run.range].underlineStyle = .single
            result[run.range].foregroundColor = Color.primary
        }
        return result
    }
}

#Preview {
    ScrollView {
        MarkdownView(markdown: "# Title\n\nSome **bold** text and `code`.\n\n- one\n- two\n\n```\nlet value = 1\n```")
            .padding()
    }
}
