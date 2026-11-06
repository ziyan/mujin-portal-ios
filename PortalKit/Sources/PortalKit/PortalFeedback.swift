import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// PortalFeedbackRequest is what the app sends when a person tells the Portal team what is wrong with the app, or what could be
/// better. The server writes the ticket's title and description, so the request carries only the person's words, the ids of the
/// pictures they uploaded, and a few facts about the app for whoever reproduces a fault.
public struct PortalFeedbackRequest: Equatable, Sendable {
    /// What the sender of the request is: this app is always "ios".
    public static let clientSurfaceName = "ios"

    public let feedbackText: String
    public let attachmentIds: [String]
    public let clientSurface: String
    public let clientVersion: String?
    public let deviceName: String?
    public let systemVersion: String?
    public let screenName: String?

    public init(
        feedbackText: String, attachmentIds: [String] = [], clientSurface: String = PortalFeedbackRequest.clientSurfaceName,
        clientVersion: String? = nil, deviceName: String? = nil, systemVersion: String? = nil, screenName: String? = nil
    ) {
        self.feedbackText = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.attachmentIds = attachmentIds
        self.clientSurface = clientSurface
        self.clientVersion = clientVersion
        self.deviceName = deviceName
        self.systemVersion = systemVersion
        self.screenName = screenName
    }

    /// The variables of the mutation. An optional fact that is empty is left out, so the server never stores a blank.
    public var variables: [String: JSONValue] {
        var variables: [String: JSONValue] = ["feedbackText": .string(feedbackText), "clientSurface": .string(clientSurface)]
        if !attachmentIds.isEmpty { variables["attachmentIds"] = .array(attachmentIds.map { .string($0) }) }
        for (name, value) in [
            ("clientVersion", clientVersion), ("deviceName", deviceName), ("systemVersion", systemVersion), ("screenName", screenName),
        ] {
            if let value, !value.isEmpty { variables[name] = .string(value) }
        }
        return variables
    }
}

/// PortalFeedback holds the rules of feedback about Portal itself that do not depend on a screen.
public enum PortalFeedback {
    /// The most pictures one piece of feedback holds, the same limit the server applies.
    public static let maximumAttachmentCount = 10

    /// What the server puts in front of the person's words in the title of the ticket it opens.
    public static let titlePrefix = "Portal feedback: "

    /// Whether there are words to send. Send stays off until there are.
    public static func canSend(feedbackText: String, isSending: Bool) -> Bool {
        !isSending && !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The person's words as a row shows them: the ticket's title without the prefix the server added.
    public static func shownWords(title: String?) -> String {
        var words = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if words.hasPrefix(titlePrefix) { words = String(words.dropFirst(titlePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return words
    }

    /// The feedback tickets of one person, the most recently changed first. The server already limits the list to the person's own;
    /// this keeps another person's ticket out should a server ever send one, and keeps the flag honest on a server that sends it.
    public static func ownTickets(_ tickets: [Ticket], userId: String) -> [Ticket] {
        tickets.filter { $0.isPortalFeedback != false && ($0.requesterUserId ?? userId) == userId }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }
}

extension ServerCapabilities {
    /// Feedback about Portal itself: sending it and listing what the person sent. One release of the server brings both, and the
    /// ticket field that marks such a ticket, so the app asks for the field only here.
    public var offersPortalFeedback: Bool { offersMutation("SubmitPortalFeedback") && offersQuery("ListTickets") }
}

extension Documents {
    /// The ticket a feedback submission opened. The server names the fields the app needs to say "ticket #12 was opened".
    public static let submitPortalFeedback = """
        mutation SubmitPortalFeedback(
          $feedbackText: String!, $attachmentIds: [String!], $clientSurface: String!, $clientVersion: String, $deviceName: String,
          $systemVersion: String, $screenName: String
        ) {
          SubmitPortalFeedback(
            feedbackText: $feedbackText, attachmentIds: $attachmentIds, clientSurface: $clientSurface, clientVersion: $clientVersion,
            deviceName: $deviceName, systemVersion: $systemVersion, screenName: $screenName
          ) { ticket { id sequence title status isPortalFeedback } }
        }
        """

    /// The feedback the person sent, as the tickets they asked for.
    public static let listPortalFeedback = """
        query ListPortalFeedback($requesterUserId: String, $options: ListOptionsInput) {
          ListTickets(isPortalFeedback: true, requesterUserId: $requesterUserId, options: $options) {
            tickets { \(ticketFields) isPortalFeedback }
            meta { totalCount }
          }
        }
        """

    /// A ticket document with the flag that marks feedback about Portal added to the ticket's fields. Used only where the server
    /// offers Portal feedback, since an older server has no such field.
    public static func withPortalFeedbackFlag(_ document: String) -> String {
        document.replacingOccurrences(of: "viewerCapabilities", with: "viewerCapabilities isPortalFeedback")
    }

    static var portalFeedbackDocuments: [String] {
        [submitPortalFeedback, listPortalFeedback, withPortalFeedbackFlag(listTickets), withPortalFeedbackFlag(getTicket)]
    }
}

extension Connection {
    /// Sends feedback about Portal itself and returns the ticket it opened. Pictures are uploaded first with `uploadAttachment`.
    public func submitPortalFeedback(_ request: PortalFeedbackRequest) async throws -> Ticket {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable { let ticket: Ticket? }
            let SubmitPortalFeedback: Created?
        }
        guard let ticket = try await execute(Documents.submitPortalFeedback, variables: request.variables, as: Answer.self).SubmitPortalFeedback?.ticket else {
            throw PortalError.unreadableAnswer
        }
        return ticket
    }

    /// The feedback the person sent, the most recently changed first.
    public func portalFeedback(requesterUserId: String, first: Int = 200) async throws -> [Ticket] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let tickets: [Ticket]? }
            let ListTickets: List?
        }
        let variables: [String: JSONValue] = ["requesterUserId": .string(requesterUserId), "options": .object(["first": .number(Double(first))])]
        let rows = try await execute(Documents.listPortalFeedback, variables: variables, as: Answer.self).ListTickets?.tickets ?? []
        return PortalFeedback.ownTickets(rows, userId: requesterUserId)
    }
}
