import Foundation

/// PortalNotification is one entry of the inbox.
public struct PortalNotification: Codable, Equatable, Identifiable, Sendable {
    public struct TicketRef: Codable, Equatable, Sendable {
        public let id: String?
        public let sequence: Int64?
        public let title: String?
    }
    public struct IncidentRef: Codable, Equatable, Sendable {
        public let id: String?
        public let title: String?
    }

    public let id: String
    /// alarm, budget_alert, incident, ticket_activity, ticket_assigned, ticket_comment, ticket_lifecycle, ticket_mentioned or agent_job_failed.
    public let kind: String
    public let readAt: String?
    public let createdAt: String?
    public let ticketId: String?
    public let ticket: TicketRef?
    public let incidentId: String?
    public let incident: IncidentRef?
    public let controllerId: String?
    public let siteName: String?
    public let organizationName: String?
    public let alarmMessage: String?
    public let agentJobName: String?
    public let agentJobFailureMessage: String?
    public let isAgentJobPaused: Bool?
    public let chatId: String?
    public let chatName: String?
    public let chatAuthorName: String?
    public let chatMessageExcerpt: String?
    /// Open this conversation for a chat message.
    public let chatConversationId: String?
    /// The assistant spoke: open `agentMessageConversationId`.
    public let agentMessageConversationId: String?
    public let agentMessageReason: String?
    public let agentMessageExcerpt: String?
    /// A question or an approval waits: `question` or `approval`.
    public let agentWaitingKind: String?
    public let agentWaitingConversationId: String?
    public let agentWaitingPrompt: String?
    public let agentWaitingToolName: String?
    public let agentGoalId: String?
    public let agentGoalTitle: String?
    public let agentGoalQuestion: String?

    public init(
        id: String, kind: String, readAt: String? = nil, createdAt: String? = nil, ticketId: String? = nil, ticket: TicketRef? = nil,
        incidentId: String? = nil, incident: IncidentRef? = nil, controllerId: String? = nil, siteName: String? = nil,
        organizationName: String? = nil, alarmMessage: String? = nil, agentJobName: String? = nil, agentJobFailureMessage: String? = nil,
        isAgentJobPaused: Bool? = nil, chatId: String? = nil, chatName: String? = nil, chatAuthorName: String? = nil,
        chatMessageExcerpt: String? = nil, chatConversationId: String? = nil, agentMessageConversationId: String? = nil,
        agentMessageReason: String? = nil, agentMessageExcerpt: String? = nil, agentWaitingKind: String? = nil,
        agentWaitingConversationId: String? = nil, agentWaitingPrompt: String? = nil, agentWaitingToolName: String? = nil,
        agentGoalId: String? = nil, agentGoalTitle: String? = nil, agentGoalQuestion: String? = nil
    ) {
        self.agentMessageConversationId = agentMessageConversationId
        self.agentMessageReason = agentMessageReason
        self.agentMessageExcerpt = agentMessageExcerpt
        self.agentWaitingKind = agentWaitingKind
        self.agentWaitingConversationId = agentWaitingConversationId
        self.agentWaitingPrompt = agentWaitingPrompt
        self.agentWaitingToolName = agentWaitingToolName
        self.agentGoalId = agentGoalId
        self.agentGoalTitle = agentGoalTitle
        self.agentGoalQuestion = agentGoalQuestion
        self.chatId = chatId
        self.chatName = chatName
        self.chatAuthorName = chatAuthorName
        self.chatMessageExcerpt = chatMessageExcerpt
        self.chatConversationId = chatConversationId
        self.id = id
        self.kind = kind
        self.readAt = readAt
        self.createdAt = createdAt
        self.ticketId = ticketId
        self.ticket = ticket
        self.incidentId = incidentId
        self.incident = incident
        self.controllerId = controllerId
        self.siteName = siteName
        self.organizationName = organizationName
        self.alarmMessage = alarmMessage
        self.agentJobName = agentJobName
        self.agentJobFailureMessage = agentJobFailureMessage
        self.isAgentJobPaused = isAgentJobPaused
    }

    public var isUnread: Bool { (readAt ?? "").isEmpty }

    /// The same entry, read as of `readAt`: what a mutation's result changes in the cache.
    public func markedRead(at readAt: String) -> PortalNotification {
        guard let data = try? JSONEncoder().encode(self), case .object(var fields)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return self }
        fields["readAt"] = .string(readAt)
        guard let updated = try? JSONEncoder().encode(JSONValue.object(fields)), let copy = try? JSONDecoder().decode(PortalNotification.self, from: updated) else { return self }
        return copy
    }
    public var date: Date? { PortalDate.parse(createdAt) }

    /// What the entry is about, in the words of the ticket, incident or job.
    public var subject: String {
        switch kind {
        case "ticket_activity", "ticket_assigned", "ticket_comment", "ticket_lifecycle", "ticket_mentioned":
            guard let ticket else { return "" }
            let title = ticket.title ?? ""
            guard let sequence = ticket.sequence else { return title }
            return "#\(sequence) \(title)".trimmingCharacters(in: .whitespaces)
        case "incident": return incident?.title ?? ""
        case "alarm": return alarmMessage ?? ""
        case "agent_job_failed": return agentJobName ?? ""
        case "agent_message": return agentMessageExcerpt ?? ""
        case "agent_waiting": return agentWaitingPrompt ?? ""
        case "agent_goal_needs_you": return agentGoalTitle ?? ""
        case "chat_message":
            // "<author> in <chat>: <excerpt>"
            let place = (chatName ?? "").isEmpty ? "" : " in \(chatName!)"
            return "\(chatAuthorName ?? "")\(place): \(chatMessageExcerpt ?? "")".trimmingCharacters(in: .whitespaces)
        default: return ""
        }
    }

    /// A further line: the failure of a job, or where an alarm is.
    public var detail: String? {
        switch kind {
        case "agent_job_failed": return (agentJobFailureMessage ?? "").isEmpty ? nil : agentJobFailureMessage
        case "alarm": return siteName ?? controllerId
        case "agent_goal_needs_you": return (agentGoalQuestion ?? "").isEmpty ? nil : agentGoalQuestion
        default: return nil
        }
    }

    /// Where tapping the entry goes.
    public var target: NotificationTarget {
        if let id = ticketId ?? ticket?.id, !id.isEmpty, kind.hasPrefix("ticket_") { return .ticket(id: id) }
        if kind == "incident" { return .incident }
        if kind == "chat_message", let id = chatConversationId, !id.isEmpty { return .chat(conversationId: id) }
        if kind == "agent_message", let id = agentMessageConversationId, !id.isEmpty { return .conversation(id: id) }
        if kind == "agent_waiting", let id = agentWaitingConversationId, !id.isEmpty { return .conversation(id: id) }
        if kind == "agent_goal_needs_you", let id = agentGoalId, !id.isEmpty { return .goal(id: id) }
        if kind == "alarm" { return .site }
        if kind == "agent_job_failed" { return .automations }
        return .none
    }
}

public enum NotificationTarget: Equatable, Sendable {
    case ticket(id: String)
    case incident
    case site
    case automations
    case chat(conversationId: String)
    case conversation(id: String)
    case goal(id: String)
    case none
}

/// NotificationPreference says whether one kind of notification reaches one channel.
public struct NotificationPreferenceRow: Codable, Equatable, Sendable {
    public let kind: String
    /// in_app, email, push or sms.
    public let channel: String
    public let isEnabled: Bool?
    public let minimumAlarmLevel: String?
}

/// NotificationPreferences is the person's choices, with the server's defaults
/// for what they have not chosen.
public struct NotificationPreferences: Equatable, Sendable {
    public static let kinds = ["ticket_comment", "ticket_assigned", "ticket_mentioned", "ticket_lifecycle", "ticket_activity", "incident", "alarm", "budget_alert", "agent_job_failed", "chat_message", "agent_message", "agent_waiting", "agent_goal_needs_you"]
    public static let channels = ["in_app", "push", "email"]

    private var rows: [String: Bool] = [:]

    public init(rows: [NotificationPreferenceRow] = []) {
        for row in rows { self.rows["\(row.kind)|\(row.channel)"] = row.isEnabled ?? false }
    }

    /// The kinds that push by default; the others push only once chosen.
    static let pushByDefault: Set<String> = ["agent_message", "agent_waiting", "agent_goal_needs_you", "agent_job_failed", "chat_message"]

    /// In-app is always on. Push is on by default for the assistant's kinds and chat messages and off for ticket, alarm, incident and budget kinds; email is off by default for the assistant's kinds and chat messages and on for the rest.
    public func isEnabled(kind: String, channel: String) -> Bool {
        if channel == "in_app" { return true }
        if let chosen = rows["\(kind)|\(channel)"] { return chosen }
        let isAssistantOrChat = kind.hasPrefix("agent_") || kind == "chat_message"
        switch channel {
        case "push": return Self.pushByDefault.contains(kind)
        case "email": return !isAssistantOrChat
        default: return false
        }
    }

    public mutating func set(kind: String, channel: String, isEnabled: Bool) {
        rows["\(kind)|\(channel)"] = isEnabled
    }
}

extension Documents {
    public static let listNotifications = """
        query ListNotifications($options: ListOptionsInput) {
          ListNotifications(options: $options) {
            notifications {
              id kind readAt createdAt ticketId ticket { id sequence title } incidentId incident { id title } controllerId siteName organizationName
              alarmMessage agentJobName agentJobFailureMessage isAgentJobPaused
              chatId chatName chatAuthorName chatMessageExcerpt chatConversationId
              agentMessageConversationId agentMessageReason agentMessageExcerpt
              agentWaitingKind agentWaitingConversationId agentWaitingPrompt agentWaitingToolName
              agentGoalId agentGoalTitle agentGoalQuestion
            }
            meta { totalCount }
          }
        }
        """

    public static let countUnreadNotifications = "query CountUnreadNotifications { CountUnreadNotifications }"

    public static let markNotificationRead = """
        mutation MarkNotificationRead($notificationId: String) {
          MarkNotificationRead(notificationId: $notificationId) { notification { id readAt } }
        }
        """

    public static let markAllNotificationsRead = "mutation MarkAllNotificationsRead { MarkAllNotificationsRead { markedReadCount } }"

    public static let notificationPreferences = """
        query NotificationPreferences { NotificationPreferences { kind channel isEnabled minimumAlarmLevel } }
        """

    public static let setNotificationPreference = """
        mutation SetNotificationPreference($kind: String, $channel: String, $isEnabled: Boolean) {
          SetNotificationPreference(kind: $kind, channel: $channel, isEnabled: $isEnabled) { kind channel isEnabled }
        }
        """

    /// Told when a row is created; the event carries no content.
    public static let onNotification = """
        subscription OnNotification { OnNotification { type notificationId kind createdAt } }
        """

    static var notificationDocuments: [String] {
        [onNotification, listNotifications, countUnreadNotifications, markNotificationRead, markAllNotificationsRead, notificationPreferences, setNotificationPreference]
    }
}

extension Connection {
    /// The inbox, newest first.
    public func notifications(first: Int = 100) async throws -> [PortalNotification] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let notifications: [PortalNotification]? }
            let ListNotifications: List?
        }
        let rows = try await execute(Documents.listNotifications, variables: ["options": .object(["first": .number(Double(first))])], as: Answer.self)
            .ListNotifications?.notifications ?? []
        return rows.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public func unreadNotificationCount() async throws -> Int {
        struct Answer: Decodable, Sendable { let CountUnreadNotifications: Int? }
        return try await execute(Documents.countUnreadNotifications, as: Answer.self).CountUnreadNotifications ?? 0
    }

    public func markNotificationRead(id: String) async throws {
        _ = try await execute(Documents.markNotificationRead, variables: ["notificationId": .string(id)], as: JSONValue.self)
    }

    public func markAllNotificationsRead() async throws {
        _ = try await execute(Documents.markAllNotificationsRead, as: JSONValue.self)
    }

    public func notificationPreferences() async throws -> NotificationPreferences {
        struct Answer: Decodable, Sendable { let NotificationPreferences: [NotificationPreferenceRow]? }
        return NotificationPreferences(rows: try await execute(Documents.notificationPreferences, as: Answer.self).NotificationPreferences ?? [])
    }

    public func setNotificationPreference(kind: String, channel: String, isEnabled: Bool) async throws {
        _ = try await execute(
            Documents.setNotificationPreference, variables: ["kind": .string(kind), "channel": .string(channel), "isEnabled": .bool(isEnabled)],
            as: JSONValue.self)
    }
}
