import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Ticket is one support ticket as the list and the thread show it.
public struct Ticket: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sequence: Int64?
    public let title: String?
    public let description: String?
    /// `new`, `open`, `pending`, `hold`, `solved` or `closed`.
    public let status: String?
    /// `low`, `normal`, `high` or `urgent`.
    public let priority: String?
    public let siteId: String?
    public let organizationId: String?
    public let authorUserId: String?
    public let requesterUserId: String?
    public let assigneeUserId: String?
    public let assigneeUserIds: [String]?
    public let isInternal: Bool?
    public let externalStatusLabel: String?
    public let createdAt: String?
    public let modifiedAt: String?
    public let solvedAt: String?
    public let closedAt: String?
    public let viewerCapabilities: [String]?

    public init(
        id: String, sequence: Int64? = nil, title: String? = nil, description: String? = nil, status: String? = nil, priority: String? = nil,
        siteId: String? = nil, organizationId: String? = nil, authorUserId: String? = nil, requesterUserId: String? = nil,
        assigneeUserId: String? = nil, assigneeUserIds: [String]? = nil, isInternal: Bool? = nil, externalStatusLabel: String? = nil,
        createdAt: String? = nil, modifiedAt: String? = nil, solvedAt: String? = nil, closedAt: String? = nil, viewerCapabilities: [String]? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.siteId = siteId
        self.organizationId = organizationId
        self.authorUserId = authorUserId
        self.requesterUserId = requesterUserId
        self.assigneeUserId = assigneeUserId
        self.assigneeUserIds = assigneeUserIds
        self.isInternal = isInternal
        self.externalStatusLabel = externalStatusLabel
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.solvedAt = solvedAt
        self.closedAt = closedAt
        self.viewerCapabilities = viewerCapabilities
    }

    public var lastActivity: Date? { PortalDate.parse(modifiedAt) ?? PortalDate.parse(createdAt) }
    public var isOpenForWork: Bool { TicketTab.open.contains(status) }
    public var assigneeIds: [String] { Array(Set((assigneeUserIds ?? []) + [assigneeUserId].compactMap { $0 }.filter { !$0.isEmpty })) }

    /// "#12 Title", how a ticket is named in a sentence.
    public var displayName: String {
        let name = (title ?? "").isEmpty ? "Untitled" : title!
        guard let sequence else { return name }
        return "#\(sequence) \(name)"
    }
}

/// TicketComment is one comment in a ticket's thread. The first is the original request.
public struct TicketComment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let authorUserId: String?
    public let body: String?
    public let isInternal: Bool?
    public let isOriginalRequest: Bool?
    public let createdAt: String?
    public let deletedAt: String?
    public let redactedAt: String?

    public init(
        id: String, authorUserId: String? = nil, body: String? = nil, isInternal: Bool? = nil, isOriginalRequest: Bool? = nil,
        createdAt: String? = nil, deletedAt: String? = nil, redactedAt: String? = nil
    ) {
        self.id = id
        self.authorUserId = authorUserId
        self.body = body
        self.isInternal = isInternal
        self.isOriginalRequest = isOriginalRequest
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.redactedAt = redactedAt
    }

    public var date: Date? { PortalDate.parse(createdAt) }
    public var isRemoved: Bool { !(deletedAt ?? "").isEmpty || !(redactedAt ?? "").isEmpty }
}

/// TicketTab is the status tab of the ticket list.
public enum TicketTab: String, CaseIterable, Identifiable, Sendable {
    case open
    case solved
    case closed

    public var id: String { rawValue }

    /// The statuses a tab holds. New, pending and on-hold tickets still need work.
    public func contains(_ status: String?) -> Bool {
        switch self {
        case .open: ["new", "open", "pending", "hold"].contains(status ?? "")
        case .solved: status == "solved"
        case .closed: status == "closed"
        }
    }
}

/// TicketScope is whose tickets the list shows.
public enum TicketScope: String, CaseIterable, Identifiable, Sendable {
    /// Tickets the person asked for or is assigned to.
    case mine
    /// Everything the person may see: the organization's, or for staff the queue of every tenant.
    case everyone

    public var id: String { rawValue }
}

public enum TicketFilter {
    /// The tickets for a tab and scope, the most recently changed first.
    public static func apply(_ tickets: [Ticket], tab: TicketTab, scope: TicketScope, userId: String) -> [Ticket] {
        tickets.filter { ticket in
            guard tab.contains(ticket.status) else { return false }
            switch scope {
            case .everyone: return true
            case .mine: return ticket.requesterUserId == userId || ticket.authorUserId == userId || ticket.assigneeIds.contains(userId)
            }
        }
        .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    /// How many tickets each tab holds for a scope, for the tab labels.
    public static func counts(_ tickets: [Ticket], scope: TicketScope, userId: String) -> [TicketTab: Int] {
        Dictionary(uniqueKeysWithValues: TicketTab.allCases.map { ($0, apply(tickets, tab: $0, scope: scope, userId: userId).count) })
    }
}

public enum TicketQueue {
    static func priorityRank(_ priority: String?) -> Int {
        switch priority {
        case "urgent": 0
        case "high": 1
        case "normal": 2
        default: 3
        }
    }

    /// The tickets that need a person first: open ones, the most urgent
    /// first, new ones before those already being worked, the longest waiting first.
    public static func needingAttention(_ tickets: [Ticket], limit: Int) -> [Ticket] {
        Array(
            tickets.filter(\.isOpenForWork).sorted { first, second in
                if priorityRank(first.priority) != priorityRank(second.priority) { return priorityRank(first.priority) < priorityRank(second.priority) }
                if (first.status == "new") != (second.status == "new") { return first.status == "new" }
                return (first.lastActivity ?? .distantFuture) < (second.lastActivity ?? .distantFuture)
            }.prefix(limit))
    }
}

/// AttachmentKind is how a file in a text is shown: a picture inline, a video as a card, a PDF or any other file as a row.
public enum AttachmentKind: Equatable, Sendable {
    case image
    case video
    case pdf
    case file

    /// Videos the phone can play. Other containers the web's player may handle (webm, ogg, mkv) show as files.
    private static let playableVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let otherVideoExtensions: Set<String> = ["webm", "ogv", "ogg", "mkv"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tif", "tiff"]

    /// The kind of a file from its name, with whether the text wrote it as an image (`![...]`). The extension tells a
    /// video from a picture, as the web does, since a reference carries a name and not always a content type.
    public static func of(name: String, isImageSyntax: Bool) -> AttachmentKind {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("Attachment:") { clean = String(clean.dropFirst("Attachment:".count)).trimmingCharacters(in: .whitespaces) }
        let fileExtension = clean.split(separator: ".").last.map { $0.lowercased() } ?? ""
        if playableVideoExtensions.contains(fileExtension) { return .video }
        if otherVideoExtensions.contains(fileExtension) { return .file }
        if fileExtension == "pdf" { return .pdf }
        if isImageSyntax || imageExtensions.contains(fileExtension) { return .image }
        return .file
    }
}

/// BodyPart is a piece of text: words, or a file the text holds.
public enum BodyPart: Equatable, Sendable {
    case text(String)
    case attachment(id: String, name: String, kind: AttachmentKind)
}

public enum TicketBody {
    /// The ways the web writes a file into text: `[name](attachment:<id>)`, `![name](attachment:<id>)`, the same with the
    /// download path `/api/v1/attachment/<id>`, and `<video src="attachment:<id>" title="name">` or `<iframe ...>` for a video or a PDF.
    private static let markdownExpression = try? NSRegularExpression(
        pattern: #"(!?)\[((?:\\.|[^\]\\])*)\]\((?:attachment:|(?:https?://[^/\s)"]+)?/api/v1/attachment/)([0-9A-Za-z_-]+)(?:[#?][^)\s]*)?\)"#)
    private static let tagExpression = try? NSRegularExpression(
        pattern: #"<(video|iframe)\b[^>]*?\bsrc="(?:attachment:|(?:https?://[^/\s)"]+)?/api/v1/attachment/)([0-9A-Za-z_-]+)[^"]*"[^>]*>(?:\s*</\1>)?"#, options: [.caseInsensitive])
    private static let titleExpression = try? NSRegularExpression(pattern: #"\btitle="([^"]*)""#, options: [.caseInsensitive])

    /// Splits text holding file references into words and files, in order.
    public static func parts(_ body: String) -> [BodyPart] {
        let whole = NSRange(body.startIndex..., in: body)
        struct Found {
            let range: Range<String.Index>
            let id: String
            let name: String
            let kind: AttachmentKind
        }
        var found: [Found] = []
        for match in markdownExpression?.matches(in: body, range: whole) ?? [] {
            guard let range = Range(match.range, in: body), let bang = Range(match.range(at: 1), in: body),
                let name = Range(match.range(at: 2), in: body), let id = Range(match.range(at: 3), in: body)
            else { continue }
            let fileName = unescape(String(body[name]))
            found.append(Found(range: range, id: String(body[id]), name: fileName, kind: .of(name: fileName, isImageSyntax: !body[bang].isEmpty)))
        }
        for match in tagExpression?.matches(in: body, range: whole) ?? [] {
            guard let range = Range(match.range, in: body), let tag = Range(match.range(at: 1), in: body), let id = Range(match.range(at: 2), in: body) else { continue }
            let text = String(body[range])
            var title = ""
            if let titleMatch = titleExpression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let titleRange = Range(titleMatch.range(at: 1), in: text) {
                title = String(text[titleRange]).replacingOccurrences(of: "&quot;", with: "\"")
            }
            var kind: AttachmentKind = body[tag].lowercased() == "video" ? .video : .pdf
            if kind == .video, !title.isEmpty, AttachmentKind.of(name: title, isImageSyntax: false) == .file { kind = .file }
            found.append(Found(range: range, id: String(body[id]), name: title, kind: kind))
        }
        var parts: [BodyPart] = []
        var cursor = body.startIndex
        for item in found.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) where item.range.lowerBound >= cursor {
            let before = String(body[cursor..<item.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { parts.append(.text(before)) }
            parts.append(.attachment(id: item.id, name: item.name, kind: item.kind))
            cursor = item.range.upperBound
        }
        let rest = String(body[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { parts.append(.text(rest)) }
        return parts
    }

    static func unescape(_ name: String) -> String {
        var result = ""
        var isEscaped = false
        for character in name {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// True when the text holds at least one file reference.
    public static func hasAttachments(_ body: String) -> Bool {
        parts(body).contains { if case .attachment = $0 { true } else { false } }
    }
}

extension Documents {
    static let ticketFields = """
        id sequence title status priority siteId organizationId authorUserId requesterUserId assigneeUserId assigneeUserIds isInternal
        externalStatusLabel createdAt modifiedAt solvedAt closedAt viewerCapabilities
        """

    static let commentFields = "id authorUserId body isInternal isOriginalRequest createdAt deletedAt redactedAt"

    public static let listTickets = """
        query ListTickets($organizationId: String, $siteId: String, $controllerId: String, $virtualControllerId: String, $options: ListOptionsInput) {
          ListTickets(organizationId: $organizationId, siteId: $siteId, controllerId: $controllerId, virtualControllerId: $virtualControllerId, options: $options) {
            tickets { \(ticketFields) }
            meta { totalCount }
          }
        }
        """

    public static let getTicket = """
        query GetTicket($ticketId: String) {
          GetTicket(ticketId: $ticketId) { \(ticketFields) description }
        }
        """

    public static let getTicketBySequence = """
        query GetTicketBySequence($sequence: Int64!) {
          GetTicketBySequence(sequence: $sequence) { \(ticketFields) description }
        }
        """

    public static let listTicketComments = """
        query ListTicketComments($ticketId: String) {
          ListTicketComments(ticketId: $ticketId) { \(commentFields) }
        }
        """

    public static let createTicketComment = """
        mutation CreateTicketComment($ticketId: String, $body: String, $isInternal: Boolean) {
          CreateTicketComment(ticketId: $ticketId, body: $body, isInternal: $isInternal) { ticketComment { \(commentFields) } }
        }
        """

    public static let closeTicket = """
        mutation CloseTicket($ticketId: String, $reason: String) {
          CloseTicket(ticketId: $ticketId, reason: $reason) { ticket { id status } }
        }
        """

    public static let reopenTicket = """
        mutation ReopenTicket($ticketId: String) {
          ReopenTicket(ticketId: $ticketId) { ticket { id status } }
        }
        """

    public static let getUser = """
        query GetUser($userId: String) { GetUser(userId: $userId) { id name email organizationId } }
        """

    public static let listOrganizations = """
        query ListOrganizations($options: ListOptionsInput) {
          ListOrganizations(options: $options) { organizations { id name isMujin isActive hasLogo modifiedAt } meta { totalCount } }
        }
        """

    static var ticketDocuments: [String] {
        [listTickets, getTicket, getTicketBySequence, listTicketComments, createTicketComment, closeTicket, reopenTicket, getUser, listOrganizations]
    }
}

/// OrganizationSummary is an organization in a picker.
public struct OrganizationSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let isMujin: Bool?
    public let isActive: Bool?
    public let hasLogo: Bool?
    public let modifiedAt: String?

    public init(id: String, name: String?, isMujin: Bool? = nil, isActive: Bool? = nil, hasLogo: Bool? = nil, modifiedAt: String? = nil) {
        self.hasLogo = hasLogo
        self.modifiedAt = modifiedAt
        self.id = id
        self.name = name
        self.isMujin = isMujin
        self.isActive = isActive
    }
}

/// PersonSummary is a person as a name beside a comment or a ticket.
public struct PersonSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let email: String?
    public let organizationId: String?

    public init(id: String, name: String? = nil, email: String? = nil, organizationId: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.organizationId = organizationId
    }

    /// The name, else the email, else nothing.
    public var shownName: String? {
        if let name, !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        return nil
    }
}

extension Connection {
    /// Tickets the person may see, newest change first. For staff with no
    /// organization it is the queue across organizations.
    public func tickets(organizationId: String? = nil, siteId: String? = nil, controllerId: String? = nil, virtualControllerId: String? = nil, first: Int = 200) async throws -> [Ticket] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let tickets: [Ticket]? }
            let ListTickets: List?
        }
        var variables: [String: JSONValue] = ["options": .object(["first": .number(Double(first))])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        if let siteId { variables["siteId"] = .string(siteId) }
        if let controllerId { variables["controllerId"] = .string(controllerId) }
        if let virtualControllerId { variables["virtualControllerId"] = .string(virtualControllerId) }
        let rows = try await execute(Documents.listTickets, variables: variables, as: Answer.self).ListTickets?.tickets ?? []
        return rows.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    public func ticket(id: String) async throws -> Ticket {
        struct Answer: Decodable, Sendable { let GetTicket: Ticket? }
        guard let ticket = try await execute(Documents.getTicket, variables: ["ticketId": .string(id)], as: Answer.self).GetTicket else {
            throw PortalError.refused("Ticket not found.")
        }
        return ticket
    }

    /// The ticket a web address names: Portal's pages say "#12", the sequence, not the id.
    public func ticket(sequence: Int64) async throws -> Ticket {
        struct Answer: Decodable, Sendable { let GetTicketBySequence: Ticket? }
        guard let ticket = try await execute(Documents.getTicketBySequence, variables: ["sequence": .number(Double(sequence))], as: Answer.self).GetTicketBySequence else {
            throw PortalError.refused("Ticket not found.")
        }
        return ticket
    }

    /// The thread, oldest first, without comments that were deleted.
    public func ticketComments(ticketId: String) async throws -> [TicketComment] {
        struct Answer: Decodable, Sendable { let ListTicketComments: [TicketComment]? }
        let rows = try await execute(Documents.listTicketComments, variables: ["ticketId": .string(ticketId)], as: Answer.self).ListTicketComments ?? []
        return rows.filter { ($0.deletedAt ?? "").isEmpty }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    @discardableResult
    public func addTicketComment(ticketId: String, body: String, isInternal: Bool = false) async throws -> TicketComment? {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable { let ticketComment: TicketComment? }
            let CreateTicketComment: Created?
        }
        let variables: [String: JSONValue] = ["ticketId": .string(ticketId), "body": .string(body), "isInternal": .bool(isInternal)]
        return try await execute(Documents.createTicketComment, variables: variables, as: Answer.self).CreateTicketComment?.ticketComment
    }

    /// Closes a ticket as resolved.
    public func closeTicket(id: String) async throws {
        _ = try await execute(Documents.closeTicket, variables: ["ticketId": .string(id), "reason": .string("resolved")], as: JSONValue.self)
    }

    public func reopenTicket(id: String) async throws {
        _ = try await execute(Documents.reopenTicket, variables: ["ticketId": .string(id)], as: JSONValue.self)
    }

    public func person(id: String) async throws -> PersonSummary? {
        struct Answer: Decodable, Sendable { let GetUser: PersonSummary? }
        return try await execute(Documents.getUser, variables: ["userId": .string(id)], as: Answer.self).GetUser
    }

    /// Every organization, for Mujin users choosing a customer.
    public func organizations(first: Int = 500) async throws -> [OrganizationSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let organizations: [OrganizationSummary]? }
            let ListOrganizations: List?
        }
        let rows = try await execute(Documents.listOrganizations, variables: ["options": .object(["first": .number(Double(first))])], as: Answer.self)
            .ListOrganizations?.organizations ?? []
        return rows.filter { $0.isActive != false }.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    }

    /// Uploads a file to Portal's attachment store and returns how to refer to it.
    public func uploadAttachment(data: Data, filename: String, contentType: String) async throws -> UploadedFile {
        guard Int64(data.count) <= SharePayload.maximumFileBytes else { throw PortalError.refused(SharePayload.tooLargeMessage(name: filename, byteCount: Int64(data.count))) }
        let boundary = "portal-\(UUID().uuidString)"
        var request = URLRequest(url: account.server.endpoint("/api/v1/attachment"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartBody.body(boundary: boundary, filename: filename, contentType: contentType, content: data)
        let (answer, response) = try await send(authorizing: request)
        switch response.statusCode {
        case 200, 201:
            struct Stored: Decodable { let id: String? }
            guard let id = (try? JSONDecoder().decode(Stored.self, from: answer))?.id, !id.isEmpty else { throw PortalError.unreadableAnswer }
            return UploadedFile(id: id, filename: filename, contentType: contentType)
        case 401, 403: throw PortalError.refused(ShareSender.uploadsNotAccepted)
        case 413: throw PortalError.refused(ShareSender.tooLarge)
        default: throw PortalError.refused("HTTP \(response.statusCode)")
        }
    }
}

extension MultipartBody {
    /// The body of a one-file multipart form held in memory, for small files.
    public static func body(boundary: String, filename: String, contentType: String, content: Data) -> Data {
        let safeName = filename.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8)
        body.append(content)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

extension SharePayload {
    /// The sentence for a file over the limit, naming the file, its size and the limit.
    public static func tooLargeMessage(name: String, byteCount: Int64, limit: Int64 = maximumFileBytes) -> String {
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .binary)
        let limitText = ByteCountFormatter.string(fromByteCount: limit, countStyle: .binary)
        return "\(name) is \(size). The most you can attach is \(limitText)."
    }
}

/// AttachmentLimits are the app's own limits on what goes into one message,
/// the same as the web app's. The server takes more, but a file the web app
/// would refuse is refused here before it is uploaded.
public enum AttachmentLimits {
    public static let maximumFileBytes: Int64 = 10 << 20
    public static let maximumFileCount = 10

    /// Why a file cannot be added, in words that name the file, its size and the limit; nil when it can.
    public static func refusal(name: String, byteCount: Int64, alreadyAttached: Int) -> String? {
        if alreadyAttached >= maximumFileCount { return "You can attach up to \(maximumFileCount) files to one message." }
        if byteCount > maximumFileBytes { return SharePayload.tooLargeMessage(name: name, byteCount: byteCount, limit: maximumFileBytes) }
        return nil
    }
}
