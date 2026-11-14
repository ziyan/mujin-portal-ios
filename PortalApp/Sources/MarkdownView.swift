import PortalKit
import SwiftUI
import UIKit

/// MarkdownView lays out an assistant answer. Blocks come from PortalKit's
/// splitter; the system renders the bold, italic, code and links inside them.
struct MarkdownView: View {
    let markdown: String
    var isSelectable = true
    /// The names of the people and agents mentioned, which read as chips in the words. Code is left as typed.
    var mentionNames: [String] = []
    /// Whether the words sit on the accent color, which the chips then lighten instead of tint.
    var isOnAccent = false

    @ViewBuilder
    var body: some View {
        if isSelectable {
            blocks.textSelection(.enabled)
        } else {
            blocks
        }
    }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlocks.parse(MemoryCitation.linking(markdown)).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            if RichMath.hasFormula(text) {
                // A paragraph that holds a formula stays text: each formula is drawn on its own and set in the words.
                InlineMathText(text: text) { words in Self.chips(Self.inline(words), names: mentionNames, isOnAccent: isOnAccent) }
            } else {
                Text(Self.chips(Self.inline(text), names: mentionNames, isOnAccent: isOnAccent))
            }
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .code(let language, let text):
            if let chart = AnswerChart.parse(language: language, text: text) {
                AnswerChartView(chart: chart)
            } else if language == "math" {
                // A formula on its own line, drawn with KaTeX, or its source where it cannot be.
                RichDrawing(content: .formula(text), identifier: "mathFormula") { codeBlock(text, language: "math") }
            } else if language.split(separator: " ").first == "mermaid" {
                // A diagram sits under the code block's header; one that cannot be drawn shows its source there.
                CodeFrame(language: "mermaid", source: text) {
                    RichDrawing(content: .diagram(text), identifier: "mermaidDiagram") { codeBody(text).accessibilityIdentifier("markdownCode") }
                }
            } else {
                codeBlock(text, language: language)
            }

        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListItemView(item: item, text: Self.chips(Self.inline(item.text), names: mentionNames, isOnAccent: isOnAccent))
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

    /// Code as typed, which scrolls sideways rather than wrap. A diagram or formula the app cannot draw shows its source this way.
    private func codeBlock(_ text: String, language: String) -> some View {
        CodeFrame(language: language, source: text) { codeBody(text) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("markdownCode")
    }

    private func codeBody(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.callout.monospaced())
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        // Web addresses typed as plain text become links too, which the
        // app opens in its own browser. Code and existing links stay as they are.
        let result = (try? AttributedString(markdown: BareLinks.markdown(AnswerMath.inlineAsCode(text)), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        return styledLinks(result)
    }

    /// The names of the people mentioned as chips: semibold on a tint. Words in code are left as they are.
    static func chips(_ text: AttributedString, names: [String], isOnAccent: Bool) -> AttributedString {
        guard !names.isEmpty else { return text }
        var result = text
        for span in Mentions.spans(in: String(text.characters), names: names) {
            guard let start = AttributedString.Index(span.lowerBound, within: result), let end = AttributedString.Index(span.upperBound, within: result) else { continue }
            if result[start..<end].runs.contains(where: { $0.inlinePresentationIntent?.contains(.code) == true }) { continue }
            result[start..<end].font = .body.weight(.semibold)
            result[start..<end].backgroundColor = isOnAccent ? Color.onAccent.opacity(0.25) : Color.accentColor.opacity(0.18)
        }
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

/// MarkdownListItemView is one item of a list: indented by its level, after its bullet, its number or its task's box.
private struct MarkdownListItemView: View {
    let item: MarkdownListItem
    let text: AttributedString
    @ScaledMetric(relativeTo: .body) private var levelIndent: CGFloat = 18

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch (item.isChecked, item.marker) {
            case (let isChecked?, _):
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(isChecked ? Text("Done") : Text("Not done"))
                    .accessibilityIdentifier(isChecked ? "markdownTaskBoxDone" : "markdownTaskBox")
            case (nil, .number(let number)):
                Text("\(number).").monospacedDigit()
            case (nil, .bullet):
                // A deeper bullet is hollow, then square, as on the web.
                Text(["\u{2022}", "\u{25E6}", "\u{25AA}"][min(item.level, 2)])
            }
            Text(text)
        }
        .padding(.leading, CGFloat(item.level) * levelIndent)
    }
}

/// MarkdownTableView is a table of an answer or a page: a header row in semibold, thin separators between rows, every other body
/// row tinted, and each column aligned as the Markdown says. The cells never wrap or truncate, so a table wider than its row scrolls
/// sideways with a drag, at any text size. A pinch on the table, or its full screen button, opens it full screen, where it can be
/// pinched, dragged both ways and double tapped, as a picture is. The web draws the same table with a rounded border and a tinted header.
private struct MarkdownTableView: View {
    let headerCells: [String]
    let columnAlignments: [MarkdownColumnAlignment]
    let bodyRows: [[String]]

    /// The rows drawn at a time. The grid lays out every cell it holds at once, which a table of hundreds of rows would make the
    /// screen wait for, so a long table starts with this many and adds as many again on a tap.
    private static let rowsPerPart = 100

    @State private var shownRowCount = Self.rowsPerPart

    /// The width of the row the table sits in, which a table narrower than it fills.
    @State private var rowWidth: CGFloat = 0

    /// Whether the full screen viewer is open, and the table drawn as a picture for it, which is made just after it opens.
    @State private var isFullScreenOpen = false
    @State private var fullScreenPicture: UIImage?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The table fills the row, and scrolls sideways when it is wider. Asking first whether it fits drew a wide table on a
            // wide screen as fitting and then wider than its row, which pushed the words around it off the screen.
            ScrollView(.horizontal, showsIndicators: false) {
                grid.frame(minWidth: rowWidth, idealWidth: rowWidth, maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in rowWidth = width }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MarkdownTableGrid.frameColor, lineWidth: 1))
            // Two fingers spreading on the table open it full screen; one finger still drags it sideways, and the page scrolls as before.
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.05).onChanged { value in
                    if value.magnification > 1.12 { openFullScreen() }
                }
            )
            // Text selection on the page's words reaches over the table too, which is kept from taking the finger that drags it.
            .textSelection(.disabled)
            .accessibilityIdentifier("markdownTable")
            .accessibilityAction(named: Text("Open full screen")) { openFullScreen() }
            HStack {
                if shownRowCount < bodyRows.count {
                    Button {
                        shownRowCount += Self.rowsPerPart
                    } label: {
                        Text("Show more (\(shownRowCount) of \(bodyRows.count) rows)")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("markdownTableShowMoreButton")
                }
                Spacer(minLength: 0)
                Button {
                    openFullScreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open the table full screen")
                .accessibilityIdentifier("markdownTableOpenButton")
            }
        }
        .fullScreenCover(isPresented: $isFullScreenOpen, onDismiss: { fullScreenPicture = nil }) {
            MarkdownTableViewer(picture: fullScreenPicture)
        }
        .task {
            // The screenshot run opens the viewer, since a pinch cannot be scripted there.
            guard DemoOptions.screen == "site-page-table-zoom" else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            openFullScreen()
        }
    }

    private var grid: some View {
        MarkdownTableGrid(headerCells: headerCells, columnAlignments: columnAlignments, bodyRows: Array(bodyRows.prefix(shownRowCount)))
    }

    /// Opens the viewer at once, then draws the rows shown so far as a picture, once, in the person's appearance and text size. The
    /// drawing waits a moment so the viewer is on screen, with a spinner, before the main thread is busy with it.
    private func openFullScreen() {
        guard !isFullScreenOpen else { return }
        isFullScreenOpen = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard isFullScreenOpen, fullScreenPicture == nil else { return }
            fullScreenPicture = MarkdownTablePicture.render(
                grid, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, displayScale: displayScale)
        }
    }
}

/// MarkdownTableGrid is the cells of a table and the lines between them, drawn in the row and, as a picture, full screen.
struct MarkdownTableGrid: View {
    let headerCells: [String]
    let columnAlignments: [MarkdownColumnAlignment]
    let bodyRows: [[String]]

    // Translucent greys, as on the web, so the table suits the person's tinted bubble and the grey one in both themes.
    static let frameColor = Color.gray.opacity(0.28)
    private static let headerColor = Color.gray.opacity(0.10)
    private static let headerRuleColor = Color.gray.opacity(0.35)
    private static let rowRuleColor = Color.gray.opacity(0.18)
    private static let bandColor = Color.gray.opacity(0.05)

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headerCells.enumerated()), id: \.offset) { column, cell in
                    cellView(cell, column: column, isHeader: true)
                        .background { Rectangle().fill(Self.headerColor) }
                }
            }
            // A firmer rule under the header, a fainter one between rows, and none after the last.
            Rectangle().fill(Self.headerRuleColor).frame(height: 1)
            ForEach(Array(bodyRows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 { Rectangle().fill(Self.rowRuleColor).frame(height: 0.5) }
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        cellView(cell, column: column, isHeader: false)
                            .background { Rectangle().fill(rowIndex % 2 == 1 ? Self.bandColor : Color.clear) }
                    }
                }
            }
        }
    }

    /// One cell, aligned as its column says, header included. Digits are all one width, so a column of numbers lines up.
    private func cellView(_ text: String, column: Int, isHeader: Bool) -> some View {
        let alignment = column < columnAlignments.count ? columnAlignments[column] : .leading
        return Text(MarkdownView.inline(text))
            .font(isHeader ? .caption.weight(.semibold) : .callout)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    }
}

/// MarkdownTablePicture draws a table at its natural size as a picture, sharp enough to zoom into, on the page's own background.
@MainActor
enum MarkdownTablePicture {
    /// The longest side of the picture, in pixels, so a long table does not ask for more memory than a phone has to spare.
    static let maximumPixelSide: CGFloat = 4_096
    /// The most pixels the picture may hold in all, about 48 MB at four bytes each, however the table is shaped.
    static let maximumPixelCount: CGFloat = 12_000_000
    /// How many times sharper than the screen the picture is drawn, so it stays crisp zoomed in.
    static let zoomSharpness: CGFloat = 3

    /// The picture is drawn once, at a scale worked out from the table's laid out size, which costs a layout and not a drawing.
    static func render(_ grid: some View, colorScheme: ColorScheme, dynamicTypeSize: DynamicTypeSize, displayScale: CGFloat) -> UIImage? {
        let content = grid
            .fixedSize()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MarkdownTableGrid.frameColor, lineWidth: 1))
            .padding(16)
            .background(Color(uiColor: .systemBackground))
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        let size = UIHostingController(rootView: content).sizeThatFits(in: CGSize(width: 100_000, height: 100_000))
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = max(
            0.25, min(displayScale * zoomSharpness, maximumPixelSide / max(size.width, size.height), (maximumPixelCount / (size.width * size.height)).squareRoot()))
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// MarkdownTableViewer shows a table full screen as the picture viewer shows a picture: pinch to zoom around the fingers, drag both
/// ways, double tap to zoom in and back, and close with the button or a swipe down when the whole table shows.
struct MarkdownTableViewer: View {
    @Environment(\.dismiss) private var dismiss
    /// The table's picture, or nil while it is being drawn.
    let picture: UIImage?

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let picture {
                ZoomableImage(image: picture, onDismiss: { dismiss() })
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel("Table")
                    .accessibilityIdentifier("markdownTableViewer")
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("markdownTableViewerCloseButton")
                Spacer()
                if let picture {
                    ShareLink(item: Image(uiImage: picture), preview: SharePreview(String(localized: "Table"), image: Image(uiImage: picture))) {
                        Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Share")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

#Preview {
    ScrollView {
        MarkdownView(markdown: "# Title\n\nSome **bold** text and `code`.\n\n- one\n- two\n\n| Station | Picks |\n| --- | ---: |\n| One | 120 |\n\n```\nlet value = 1\n```")
            .padding()
    }
}
