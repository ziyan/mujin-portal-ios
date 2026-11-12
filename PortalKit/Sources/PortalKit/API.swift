import Foundation

/// The things the app asks of Portal, one function each.
extension Connection {
    public func me() async throws -> Me {
        struct Answer: Decodable, Sendable { let Me: Me }
        return try await execute(Documents.me, as: Answer.self).Me
    }

    /// The person with what decides their navigation. When the organization
    /// cannot be read, the permissions decide.
    public func profile() async throws -> Profile {
        struct Answer: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                let name: String?
                let isMujin: Bool?
            }
            let GetOrganization: Row?
        }
        let me = try await me()
        guard let organizationId = me.organizationId, !organizationId.isEmpty,
            let answer = try? await execute(Documents.organization, variables: ["organizationId": .string(organizationId)], as: Answer.self)
        else { return Profile(me: me) }
        return Profile(me: me, organizationName: answer.GetOrganization?.name, isMujinOrganization: answer.GetOrganization?.isMujin)
    }

    public func mainAgent() async throws -> Agent {
        struct Answer: Decodable, Sendable { let GetMainAgent: Agent }
        return try await execute(Documents.mainAgent, as: Answer.self).GetMainAgent
    }

    /// The person's own conversations, newest first.
    public func conversations(userId: String) async throws -> [ConversationSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let conversations: [ConversationSummary]? }
            let ListConversations: List
        }
        let answer = try await execute(
            Documents.listConversations, variables: ["userId": .string(userId), "conversationKind": .string("assistant")], as: Answer.self)
        return ConversationOrdering.ordered(answer.ListConversations.conversations ?? [])
    }

    public func conversation(id: String) async throws -> ConversationSummary {
        struct Answer: Decodable, Sendable { let GetConversation: ConversationSummary }
        return try await execute(Documents.getConversation, variables: ["conversationId": .string(id)], as: Answer.self).GetConversation
    }

    public func messages(conversationId: String) async throws -> [ConversationMessage] {
        struct Answer: Decodable, Sendable { let ListConversationMessages: [ConversationMessage]? }
        return try await execute(Documents.listMessages, variables: ["conversationId": .string(conversationId)], as: Answer.self)
            .ListConversationMessages ?? []
    }

    /// The questions and approvals still waiting for the person.
    public func waitingCards(conversationId: String) async throws -> (questions: [QuestionCard], approvals: [ApprovalCard]) {
        struct Questions: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                let id: String
                let question: String?
                let choices: [String]?
                let allowOther: Bool?
                let askedAt: String?
                let answeredAt: String?
                let cancelledAt: String?
            }
            let ListConversationQuestions: [Row]?
        }
        struct Approvals: Decodable, Sendable {
            struct Row: Decodable, Sendable {
                let id: String
                let toolCallId: String?
                let toolName: String?
                let policyReason: String?
                let risk: String?
                let arguments: String?
                let decidedAt: String?
                let cancelledAt: String?
            }
            let ListConversationApprovals: [Row]?
        }
        let variables: [String: JSONValue] = ["conversationId": .string(conversationId)]
        async let questionRows = execute(Documents.listQuestions, variables: variables, as: Questions.self)
        async let approvalRows = execute(Documents.listApprovals, variables: variables, as: Approvals.self)
        let questions = try await questionRows.ListConversationQuestions ?? []
        let approvals = try await approvalRows.ListConversationApprovals ?? []
        return (
            questions.filter { ($0.answeredAt ?? "").isEmpty && ($0.cancelledAt ?? "").isEmpty }.map {
                QuestionCard(
                    id: $0.id, question: $0.question ?? "", choices: $0.choices ?? [], allowOther: $0.allowOther ?? true, askedAt: $0.askedAt)
            },
            approvals.filter { ($0.decidedAt ?? "").isEmpty && ($0.cancelledAt ?? "").isEmpty }.map {
                ApprovalCard(
                    id: $0.id, toolCallId: $0.toolCallId ?? "", toolName: $0.toolName ?? "", policyReason: $0.policyReason ?? "",
                    risk: $0.risk ?? "", arguments: $0.arguments ?? "")
            }
        )
    }

    /// The person's main chat, made on first use. Nothing changes when it already exists. Throws when the organization has no main agent.
    public func ensureMainConversation() async throws -> ConversationSummary {
        struct Answer: Decodable, Sendable {
            struct Ensured: Decodable, Sendable { let conversation: ConversationSummary }
            let EnsureMainConversation: Ensured
        }
        return try await execute(Documents.ensureMainConversation, as: Answer.self).EnsureMainConversation.conversation
    }

    public func createConversation(agentId: String) async throws -> ConversationSummary {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable { let conversation: ConversationSummary }
            let CreateConversation: Created
        }
        return try await execute(Documents.createConversation, variables: ["agentId": .string(agentId)], as: Answer.self)
            .CreateConversation.conversation
    }

    /// Starts a turn and returns its run id. Every send says it comes from
    /// the iOS app, so the assistant writes for a phone. `viewing` names the
    /// screen the person asks about; the server drops it silently when they
    /// may not see that resource.
    @discardableResult
    public func sendMessage(
        conversationId: String, text: String, viewing: Viewing? = nil, replyToMessageId: String? = nil, isVoice: Bool = false,
        interruptedAnswer: InterruptedAnswer? = nil, pageTitle: String? = nil
    ) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Sent: Decodable, Sendable { let runId: String? }
            let SendMessage: Sent
        }
        var variables: [String: JSONValue] = [
            "conversationId": .string(conversationId), "message": .string(text), "surface": .string("ios"),
        ]
        if let replyToMessageId, !replyToMessageId.isEmpty { variables["replyToMessageId"] = .string(replyToMessageId) }
        if isVoice {
            variables["voice"] = .bool(true)
            // Only meaningful with a spoken message: put in front of the model for that run and never stored.
            if let interruptedAnswer {
                variables["interruptedAnswer"] = .object(["heardText": .string(interruptedAnswer.heardText), "unheardText": .string(interruptedAnswer.unheardText)])
            }
        }
        // The page the person is on goes with every message to the assistant, with or without a resource:
        // the resource's own screen, else the conversation itself.
        var viewingObject: [String: JSONValue] = [:]
        if let viewing {
            viewingObject["kind"] = .string(viewing.kind)
            viewingObject["id"] = .string(viewing.id)
        }
        if let page = PageContext.path(viewing?.page ?? PortalLink.conversation(id: conversationId).path) {
            viewingObject["page"] = .string(page)
            if let title = PageContext.title(viewing?.label ?? pageTitle) { viewingObject["pageTitle"] = .string(title) }
        }
        variables["viewing"] = .object(viewingObject)
        let answer = try await execute(Documents.sendMessage, variables: variables, as: Answer.self)
        return answer.SendMessage.runId ?? ""
    }

    public func cancelRun(conversationId: String) async throws {
        _ = try await execute(Documents.cancelRun, variables: ["conversationId": .string(conversationId)], as: JSONValue.self)
    }

    public func answerQuestion(id: String, answer: String) async throws {
        _ = try await execute(
            Documents.answerQuestion, variables: ["questionId": .string(id), "answer": .string(answer)], as: JSONValue.self)
    }

    /// Approves or rejects a tool call. The verdict words are the server's.
    public func resolveToolApproval(id: String, isApproved: Bool, reason: String? = nil) async throws {
        var variables: [String: JSONValue] = ["approvalId": .string(id), "verdict": .string(isApproved ? "approved" : "rejected")]
        if let reason, !reason.isEmpty { variables["reason"] = .string(reason) }
        _ = try await execute(Documents.resolveToolApproval, variables: variables, as: JSONValue.self)
    }

    public func archiveConversation(id: String) async throws {
        _ = try await execute(
            Documents.archiveConversation, variables: ["conversationId": .string(id), "archived": .bool(true)], as: JSONValue.self)
    }
}

/// InterruptedAnswer is what the person heard of an answer before they talked over it.
public struct InterruptedAnswer: Equatable, Sendable {
    public let heardText: String
    public let unheardText: String

    public init(heardText: String, unheardText: String) {
        self.heardText = heardText
        self.unheardText = unheardText
    }
}

/// A site a ticket can be opened for.
public struct SiteSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let organizationId: String?
    public let isArchived: Bool?
    /// What the viewer may do at this site, such as `virtual_controller:create`.
    public let viewerCapabilities: [String]?
    /// The controller that stands for the whole site, when the site has one. Only a server that has the field says.
    public let telemetrySourceControllerId: String?

    public init(id: String, name: String?, organizationId: String? = nil, isArchived: Bool? = nil, viewerCapabilities: [String]? = nil, telemetrySourceControllerId: String? = nil) {
        self.telemetrySourceControllerId = telemetrySourceControllerId
        self.viewerCapabilities = viewerCapabilities
        self.id = id
        self.name = name
        self.organizationId = organizationId
        self.isArchived = isArchived
    }

    public func can(_ capability: String) -> Bool { viewerCapabilities?.contains(capability) ?? false }
}

extension Connection {
    /// The sites the person can open tickets for, by name.
    public func sites(organizationId: String? = nil, includesTelemetrySource: Bool = false) async throws -> [SiteSummary] {
        let rows = try await allSites(organizationId: organizationId, includesTelemetrySource: includesTelemetrySource)
        return rows.filter { $0.isArchived != true }.sorted { ($0.name ?? "").localizedCompare($1.name ?? "") == .orderedAscending }
    }

    /// Every site the person can see, archived ones included. The server answers in pages (50 by default, 200 at most), so
    /// this asks page after page until the total it reports is reached or a page comes back empty.
    public func allSites(organizationId: String? = nil, pageSize: Int = 200, includesTelemetrySource: Bool = false) async throws -> [SiteSummary] {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let sites: [SiteSummary]?
                let meta: Meta?
            }
            let ListSites: List
        }
        var collected: [SiteSummary] = []
        while true {
            var variables: [String: JSONValue] = ["options": .object(["first": .number(Double(pageSize)), "after": .number(Double(collected.count))])]
            if let organizationId { variables["organizationId"] = .string(organizationId) }
            let document = includesTelemetrySource ? Documents.withTelemetrySource(Documents.listSites) : Documents.listSites
            let list = try await execute(document, variables: variables, as: Answer.self).ListSites
            let page = list.sites ?? []
            collected += page
            if page.isEmpty { break }
            if let total = list.meta?.totalCount, collected.count >= total { break }
            if page.count < pageSize, list.meta?.totalCount == nil { break }
        }
        return collected
    }

    /// Opens a ticket and returns its id. `priority` is one of low, normal, high, urgent.
    public func createTicket(title: String, description: String, siteId: String?, priority: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Created: Decodable, Sendable {
                struct Row: Decodable, Sendable { let id: String }
                let ticket: Row
            }
            let CreateTicket: Created
        }
        var ticket: [String: JSONValue] = ["title": .string(title), "description": .string(description), "priority": .string(priority)]
        if let siteId, !siteId.isEmpty { ticket["siteId"] = .string(siteId) }
        return try await execute(Documents.createTicket, variables: ["ticket": .object(ticket)], as: Answer.self).CreateTicket.ticket.id
    }

    /// Whether the server offers a mutation, so the app can use a feature only
    /// once the server has it. Names are compared ignoring the first letter's case.
    public func offersMutation(_ name: String) async -> Bool {
        struct Answer: Decodable, Sendable {
            struct TypeInfo: Decodable, Sendable {
                struct Field: Decodable, Sendable { let name: String }
                let fields: [Field]?
            }
            let __type: TypeInfo?
        }
        guard let answer = try? await execute(Documents.mutationNames, as: Answer.self) else { return false }
        let wanted = name.prefix(1).lowercased() + name.dropFirst()
        return (answer.__type?.fields ?? []).contains { $0.name.prefix(1).lowercased() + $0.name.dropFirst() == wanted }
    }
}

extension Connection {
    /// A one-time address that sets this account's web session cookie for the
    /// whole domain and then goes to `target`, or nil when the server will not
    /// give one: the page then opens as it is and Portal's own login page
    /// shows. The server accepts an https address on its host or on a
    /// controller or virtual controller host under it, with no port or
    /// credentials. Open the address once, within 60 seconds.
    public func webSessionHandoff(to target: URL) async -> URL? {
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false), components.host != nil else { return nil }
        guard components.user == nil, components.password == nil else { return nil }
        components.fragment = nil
        components.port = nil
        components.scheme = "https"
        guard let wanted = components.url else { return nil }
        struct Answer: Decodable, Sendable {
            struct Handoff: Decodable, Sendable { let url: String }
            let CreateWebSessionHandoff: Handoff
        }
        guard let answer = try? await execute(Documents.createWebSessionHandoff, variables: ["targetUrl": .string(wanted.absoluteString)], as: Answer.self),
            let url = URL(string: answer.CreateWebSessionHandoff.url), url.scheme == "https" || url.scheme == "http"
        else { return nil }
        return url
    }
}
