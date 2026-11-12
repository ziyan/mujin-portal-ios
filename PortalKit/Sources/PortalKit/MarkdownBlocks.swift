import Foundation

/// MarkdownBlock is one block of an assistant answer. Inline styling (bold,
/// italic, code, links) is left to the screen, which renders each text with
/// the system's Markdown support.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String, text: String)
    /// A list, its items in order: a list nested in an item is in the same block, its items one level deeper.
    case list([MarkdownListItem])
    case quote(String)
    case rule
    case table(headerCells: [String], columnAlignments: [MarkdownColumnAlignment], bodyRows: [[String]])
}

/// MarkdownListItem is one item of a list: how deep it is nested, its bullet or number, its box when it is a task, and its words.
public struct MarkdownListItem: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)
    }

    /// 0 for an item of the list itself, 1 for an item of a list nested in one, and so on.
    public let level: Int
    public let marker: Marker
    /// Nil for an ordinary item; for a task (`- [ ]` or `- [x]`), whether its box is ticked.
    public let isChecked: Bool?
    public let text: String

    public init(level: Int = 0, marker: Marker = .bullet, isChecked: Bool? = nil, text: String) {
        self.level = level
        self.marker = marker
        self.isChecked = isChecked
        self.text = text
    }
}

/// MarkdownColumnAlignment is how a table column lines up, from the colons of
/// its delimiter row: `:---` leading (also the default), `:---:` center, `---:` trailing.
public enum MarkdownColumnAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

/// MarkdownBlocks splits Markdown into the blocks a screen lays out.
public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [MarkdownListItem] = []
        // The indentation of each level of the list being read, outermost first.
        var levelIndents: [Int] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage = ""
        var isInCode = false
        var mathLines: [String] = []
        var isInMath = false
        var mathCloser = "$$"

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !items.isEmpty { blocks.append(.list(items)) }
            if !quoteLines.isEmpty { blocks.append(.quote(quoteLines.joined(separator: "\n"))) }
            paragraph = []
            items = []
            levelIndents = []
            quoteLines = []
        }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // The index of the first line after a table, so the lines it took are skipped.
        var tableEndIndex = 0
        for (lineIndex, text) in lines.enumerated() {
            if lineIndex < tableEndIndex { continue }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if isInCode {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
                    codeLines = []
                    isInCode = false
                } else {
                    codeLines.append(text)
                }
                continue
            }
            if isInMath {
                // Display math is a block of its own, drawn where it can be and shown as its source where it cannot.
                if trimmed.hasSuffix(mathCloser) {
                    let last = String(trimmed.dropLast(mathCloser.count)).trimmingCharacters(in: .whitespaces)
                    if !last.isEmpty { mathLines.append(last) }
                    blocks.append(.code(language: "math", text: mathLines.joined(separator: "\n")))
                    mathLines = []
                    isInMath = false
                } else {
                    mathLines.append(trimmed)
                }
                continue
            }
            if let opener = ["$$", "\\["].first(where: { trimmed.hasPrefix($0) }) {
                let closer = opener == "$$" ? "$$" : "\\]"
                let rest = String(trimmed.dropFirst(opener.count))
                let isOneLine = rest.count >= closer.count && rest.hasSuffix(closer)
                let firstLine = isOneLine ? String(rest.dropLast(closer.count)) : rest
                // Plain words between the delimiters are not a formula: the line is an ordinary paragraph.
                if isOneLine ? RichMath.isFormula(firstLine.trimmingCharacters(in: .whitespaces)) : true {
                    flush()
                    mathCloser = closer
                    if isOneLine {
                        blocks.append(.code(language: "math", text: firstLine.trimmingCharacters(in: .whitespaces)))
                    } else {
                        let first = firstLine.trimmingCharacters(in: .whitespaces)
                        if !first.isEmpty { mathLines.append(first) }
                        isInMath = true
                    }
                    continue
                }
            }
            if trimmed.hasPrefix("```") {
                flush()
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                isInCode = true
            } else if trimmed.isEmpty {
                flush()
            } else if let table = table(startingAt: lineIndex, in: lines) {
                flush()
                blocks.append(table.block)
                tableEndIndex = table.endIndex
            } else if let heading = headingLevel(trimmed) {
                flush()
                blocks.append(.heading(level: heading, text: String(trimmed.dropFirst(heading + 1))))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush()
                blocks.append(.rule)
            } else if let item = listItem(trimmed) {
                let (marker, words) = item
                if items.isEmpty { flush() }
                let indent = text.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                while let last = levelIndents.last, last > indent { levelIndents.removeLast() }
                if levelIndents.last.map({ $0 < indent }) ?? true { levelIndents.append(indent) }
                let (isChecked, itemText) = taskBox(words)
                items.append(MarkdownListItem(level: levelIndents.count - 1, marker: marker, isChecked: isChecked, text: itemText))
            } else if trimmed.hasPrefix(">") {
                if quoteLines.isEmpty { flush() }
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if let last = items.last, text.hasPrefix(" ") {
                // A wrapped line of the last item.
                items[items.count - 1] = MarkdownListItem(level: last.level, marker: last.marker, isChecked: last.isChecked, text: last.text + " " + trimmed)
            } else {
                if !items.isEmpty || !quoteLines.isEmpty { flush() }
                paragraph.append(trimmed)
            }
        }
        if isInCode { blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n"))) }
        if isInMath { blocks.append(.code(language: "math", text: mathLines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// Whether the text holds a table, which is the reason to lay a message out as Markdown.
    public static func hasTable(_ markdown: String) -> Bool {
        parse(markdown).contains { block in
            if case .table = block { return true }
            return false
        }
    }

    /// A table starts at a header row with a delimiter row right under it,
    /// and runs until a blank line, a code fence or a line without a pipe.
    /// A delimiter row that is still being typed or streamed (the last line
    /// of the text, with fewer cells than the header) already makes the table,
    /// so the answer does not flip from raw pipes to a table a word later.
    static func table(startingAt index: Int, in lines: [String]) -> (block: MarkdownBlock, endIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let delimiter = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), delimiter.contains("|"), delimiter.contains("-") else { return nil }
        let headerCells = tableCells(header)
        let delimiterCells = tableCells(delimiter)
        guard !headerCells.isEmpty, !delimiterCells.isEmpty else { return nil }
        let isLastLine = index + 2 >= lines.count
        let isComplete = delimiterCells.count == headerCells.count && delimiterCells.allSatisfy { isDelimiterCell($0, isPartial: false) }
        let isStreaming = isLastLine && delimiterCells.count <= headerCells.count && delimiterCells.allSatisfy { isDelimiterCell($0, isPartial: true) }
        guard isComplete || isStreaming else { return nil }
        let columnAlignments = (0..<headerCells.count).map { column -> MarkdownColumnAlignment in
            guard column < delimiterCells.count else { return .leading }
            let cell = delimiterCells[column]
            switch (cell.hasPrefix(":"), cell.hasSuffix(":") && cell.count > 1) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }
        var bodyRows: [[String]] = []
        var endIndex = index + 2
        while endIndex < lines.count {
            let row = lines[endIndex].trimmingCharacters(in: .whitespaces)
            if row.isEmpty || row.hasPrefix("```") || !row.contains("|") { break }
            var cells = tableCells(row)
            if cells.count < headerCells.count { cells += Array(repeating: "", count: headerCells.count - cells.count) }
            bodyRows.append(Array(cells.prefix(headerCells.count)))
            endIndex += 1
        }
        return (.table(headerCells: headerCells, columnAlignments: columnAlignments, bodyRows: bodyRows), endIndex)
    }

    /// One dash or more with an optional colon at each end. A partial cell
    /// may still be only a dash, a colon or a colon and a dash.
    static func isDelimiterCell(_ cell: String, isPartial: Bool) -> Bool {
        var rest = Substring(cell)
        if rest.hasPrefix(":") { rest = rest.dropFirst() }
        if rest.hasSuffix(":") { rest = rest.dropLast() }
        if rest.isEmpty { return isPartial && !cell.isEmpty }
        return rest.allSatisfy { $0 == "-" }
    }

    /// The cells of one table row. The pipes at either end are optional, `\|`
    /// is a pipe in the text, and a pipe inside a code span does not split.
    static func tableCells(_ row: String) -> [String] {
        let characters = Array(row)
        var cells: [String] = []
        var current = ""
        var index = 0
        var isInCode = false
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == "|" {
                current.append("|")
                index += 2
                continue
            }
            if character == "`" {
                if isInCode {
                    isInCode = false
                } else if characters[(index + 1)...].contains("`") {
                    isInCode = true
                }
            }
            if character == "|", !isInCode {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        cells.append(current)
        if row.hasPrefix("|"), cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true, !cells.isEmpty, row.hasSuffix("|"), !row.hasSuffix("\\|") { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    /// An item of a list: `- `, `* ` or `+ ` before a bullet's words, or up to three digits and `. ` or `) ` before a number's.
    static func listItem(_ line: String) -> (MarkdownListItem.Marker, String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return (.bullet, String(line.dropFirst(2)))
        }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (.number(number), String(rest.dropFirst(2)))
    }

    /// A task's box at the start of an item's words, and the words after it.
    static func taskBox(_ words: String) -> (Bool?, String) {
        for (box, isChecked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where words.hasPrefix(box) {
            return (isChecked, String(words.dropFirst(box.count)))
        }
        return (nil, words)
    }
}
