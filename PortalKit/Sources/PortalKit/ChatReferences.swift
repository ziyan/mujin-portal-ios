import Foundation

/// ChatReference is a ticket, controller, virtual controller, site or cell a chat message names, resolved for the reader: what was
/// written, and when the reader may see it, what it is now. One the reader may not see, or that is gone, carries only what was written.
public struct ChatReference: Codable, Equatable, Hashable, Sendable {
    public let referenceKind: String?
    public let writtenText: String?
    public let isAccessible: Bool?
    public let targetId: String?
    public let path: String?
    public let label: String?
    public let ticketSequence: Int64?
    public let ticketTitle: String?
    public let ticketStatus: String?
    public let controllerName: String?
    public let isControllerConnected: Bool?
    public let virtualControllerName: String?
    public let siteName: String?
    public let cellName: String?
    public let cellSiteName: String?

    public init(
        referenceKind: String?, writtenText: String?, isAccessible: Bool?, targetId: String? = nil, path: String? = nil, label: String? = nil,
        ticketSequence: Int64? = nil, ticketTitle: String? = nil, ticketStatus: String? = nil, controllerName: String? = nil,
        isControllerConnected: Bool? = nil, virtualControllerName: String? = nil, siteName: String? = nil, cellName: String? = nil,
        cellSiteName: String? = nil
    ) {
        self.referenceKind = referenceKind
        self.writtenText = writtenText
        self.isAccessible = isAccessible
        self.targetId = targetId
        self.path = path
        self.label = label
        self.ticketSequence = ticketSequence
        self.ticketTitle = ticketTitle
        self.ticketStatus = ticketStatus
        self.controllerName = controllerName
        self.isControllerConnected = isControllerConnected
        self.virtualControllerName = virtualControllerName
        self.siteName = siteName
        self.cellName = cellName
        self.cellSiteName = cellSiteName
    }

    /// Whether the reader may open it: it is there and theirs to see.
    public var canOpen: Bool { isAccessible == true && !(path ?? "").isEmpty }

    /// Whether it was written as a whole web address, which its link card shows instead of a chip.
    public var isPastedLink: Bool {
        let written = (writtenText ?? "").lowercased()
        return written.hasPrefix("http://") || written.hasPrefix("https://")
    }

    /// A short name for a thread's subject, for a line with no room for the chip: "Ticket 13", else the name.
    public var subjectText: String {
        if referenceKind == "ticket", let sequence = ticketSequence { return "Ticket \(sequence)" }
        return cellName ?? label ?? writtenText ?? ""
    }

    /// What the chip says: a ticket's number and title, else the name.
    public var chipText: String {
        if referenceKind == "ticket", let sequence = ticketSequence {
            let title = ticketTitle ?? label ?? ""
            return title.isEmpty ? "#\(sequence)" : "#\(sequence) \(title)"
        }
        return label ?? controllerName ?? virtualControllerName ?? cellName ?? siteName ?? writtenText ?? ""
    }
}

/// ChatReferenceCandidate is one row of the # picker: something the person can see that a message can name.
public struct ChatReferenceCandidate: Codable, Equatable, Identifiable, Sendable {
    public let referenceKind: String?
    public let targetId: String?
    public let path: String?
    public let label: String?
    public let detailText: String?
    public var id: String { "\(referenceKind ?? "")|\(targetId ?? "")" }

    public init(referenceKind: String?, targetId: String?, path: String?, label: String?, detailText: String? = nil) {
        self.referenceKind = referenceKind
        self.targetId = targetId
        self.path = path
        self.label = label
        self.detailText = detailText
    }

    /// What the picker puts in the message: a ticket as its number, anything else as a link to its page.
    public var insertedText: String {
        if referenceKind == "ticket", let path, let number = path.split(separator: "/").last { return "#\(number)" }
        return "[\(label ?? "")](\(path ?? ""))"
    }
}

/// ChatReferences handles the references of a message: one per thing named, and where they sit in the words.
public enum ChatReferences {
    /// The server gives one reference per mention, so a message that names a ticket ten times has ten. They are kept once each, by
    /// kind and by what was written, in the order they first come.
    public static func unique(_ references: [ChatReference]) -> [ChatReference] {
        var seen = Set<String>()
        return references.filter { seen.insert("\($0.referenceKind ?? "")|\($0.writtenText ?? "")").inserted }
    }

    /// The words of a message as plain runs and the references in them, found in one pass over the words as written: each place
    /// matches the longest written text that starts there and is not part of a longer word, and the scan moves past it. Nothing found
    /// is scanned again, so a reference whose label repeats what was written cannot multiply.
    public enum Piece: Equatable {
        case text(String)
        case reference(ChatReference)
    }

    public static func pieces(of text: String, references: [ChatReference]) -> [Piece] {
        let candidates = unique(references).filter { !($0.writtenText ?? "").isEmpty }.sorted { ($0.writtenText ?? "").count > ($1.writtenText ?? "").count }
        guard !candidates.isEmpty else { return text.isEmpty ? [] : [.text(text)] }
        var pieces: [Piece] = []
        var plain = ""
        var index = text.startIndex
        while index < text.endIndex {
            let isAtWordStart = index == text.startIndex || !isWordCharacter(text[text.index(before: index)])
            var matched: (ChatReference, String.Index)?
            if isAtWordStart {
                for candidate in candidates {
                    let written = candidate.writtenText ?? ""
                    guard text[index...].hasPrefix(written) else { continue }
                    let end = text.index(index, offsetBy: written.count)
                    if end < text.endIndex, isWordCharacter(text[end]), let last = written.last, isWordCharacter(last) { continue }
                    matched = (candidate, end)
                    break
                }
            }
            if let (reference, end) = matched {
                if !plain.isEmpty { pieces.append(.text(plain)); plain = "" }
                pieces.append(.reference(reference))
                index = end
            } else {
                plain.append(text[index])
                index = text.index(after: index)
            }
        }
        if !plain.isEmpty { pieces.append(.text(plain)) }
        return pieces
    }

    private static func isWordCharacter(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" }
}

extension ServerCapabilities {
    /// References in chats, and the # picker that finds them.
    public var offersChatReferences: Bool { offersQuery("SearchChatReferences") }
}

extension Documents {
    static let chatReferenceFields = """
        references { referenceKind writtenText isAccessible targetId path label ticketSequence ticketTitle ticketStatus controllerName \
        isControllerConnected virtualControllerName siteName cellName cellSiteName }
        threadSubject { referenceKind writtenText isAccessible targetId path label ticketSequence ticketTitle ticketStatus controllerName \
        isControllerConnected virtualControllerName siteName cellName cellSiteName }
        """

    /// A document with the references added to every message's fields. Sent only to a server that has them.
    public static func withChatReferences(_ document: String) -> String {
        document.replacingOccurrences(of: "linkPreviewsRemovedAt", with: "linkPreviewsRemovedAt \(chatReferenceFields)")
    }

    public static let searchChatReferences = """
        query SearchChatReferences($query: String, $limit: Int, $chatId: String) {
          SearchChatReferences(query: $query, limit: $limit, chatId: $chatId) { referenceKind targetId path label detailText }
        }
        """
}

extension Connection {
    /// What the # picker offers for what was typed after the #: an empty query gives the chat's suggestions.
    public func searchChatReferences(query: String, chatId: String?, limit: Int = 8) async throws -> [ChatReferenceCandidate] {
        struct Answer: Decodable, Sendable { let SearchChatReferences: [ChatReferenceCandidate]? }
        var variables: [String: JSONValue] = ["query": .string(query), "limit": .number(Double(limit))]
        if let chatId, !chatId.isEmpty { variables["chatId"] = .string(chatId) }
        return try await execute(Documents.searchChatReferences, variables: variables, as: Answer.self).SearchChatReferences ?? []
    }
}

extension ChatReferences {
    /// What follows a # at the end of the draft, at the start of a word: "" for a bare #, nil when the draft does not end in one.
    public static func pickerQuery(in draft: String) -> String? {
        guard let hash = draft.lastIndex(of: "#") else { return nil }
        if hash > draft.startIndex, !draft[draft.index(before: hash)].isWhitespace { return nil }
        let query = draft[draft.index(after: hash)...]
        guard !query.contains(where: \.isWhitespace) else { return nil }
        return String(query)
    }

    /// The draft with the trailing #query replaced by what the picker puts in, and a space after it.
    public static func inserting(_ candidate: ChatReferenceCandidate, into draft: String) -> String {
        guard let hash = draft.lastIndex(of: "#") else { return draft + candidate.insertedText + " " }
        return String(draft[..<hash]) + candidate.insertedText + " "
    }
}
