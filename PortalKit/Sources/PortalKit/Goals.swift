import Foundation

/// Goal is something the person asked the assistant to keep working toward.
public struct Goal: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let organizationId: String?
    public let organizationName: String?
    public let userId: String?
    public let conversationId: String?
    public let title: String?
    public let description: String?
    /// `working`, `waiting` (shown as "Needs you"), `met` or `stopped`.
    public let goalState: String?
    public let statusLine: String?
    public let waitingQuestion: String?
    public let nextCheckAt: String?
    public let lastCheckAt: String?
    public let checkIntervalMinutes: Int?
    public let endedAt: String?
    public let turnCount: Int?
    public let todayTurnCount: Int?
    public let createdAt: String?

    public init(
        id: String, title: String? = nil, goalState: String? = "working", description: String? = nil, statusLine: String? = nil,
        waitingQuestion: String? = nil, conversationId: String? = nil, nextCheckAt: String? = nil, lastCheckAt: String? = nil,
        checkIntervalMinutes: Int? = nil, turnCount: Int? = nil, todayTurnCount: Int? = nil, userId: String? = nil, organizationId: String? = nil,
        organizationName: String? = nil, endedAt: String? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.goalState = goalState
        self.description = description
        self.statusLine = statusLine
        self.waitingQuestion = waitingQuestion
        self.conversationId = conversationId
        self.nextCheckAt = nextCheckAt
        self.lastCheckAt = lastCheckAt
        self.checkIntervalMinutes = checkIntervalMinutes
        self.turnCount = turnCount
        self.todayTurnCount = todayTurnCount
        self.userId = userId
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.endedAt = endedAt
        self.createdAt = createdAt
    }

    public var state: GoalState { GoalState(rawValue: goalState ?? "") ?? .working }
    public var nextCheck: Date? { PortalDate.parse(nextCheckAt) }
    public var lastCheck: Date? { PortalDate.parse(lastCheckAt) }
    public var isOpen: Bool { state == .working || state == .waiting }
}

public enum GoalState: String, CaseIterable, Sendable {
    case working
    /// The goal is blocked on the person: "Needs you".
    case waiting
    case met
    case stopped

    /// Needs-you goals come first, then working ones, then those that ended.
    public var sortRank: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .met: 2
        case .stopped: 3
        }
    }
}

extension Array where Element == Goal {
    public var sortedForList: [Goal] {
        sorted {
            if $0.state.sortRank != $1.state.sortRank { return $0.state.sortRank < $1.state.sortRank }
            return ($0.nextCheck ?? $0.lastCheck ?? .distantFuture) < ($1.nextCheck ?? $1.lastCheck ?? .distantFuture)
        }
    }
}

/// GoalActivity is one line of what the assistant did toward a goal.
public struct GoalActivity: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let goalId: String?
    public let activityText: String?
    public let createdAt: String?

    public init(id: String, goalId: String? = nil, activityText: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.goalId = goalId
        self.activityText = activityText
        self.createdAt = createdAt
    }

    public var date: Date? { PortalDate.parse(createdAt) }
}

/// Idea is something the assistant suggests it could do for the person.
public struct Idea: Codable, Equatable, Identifiable, Sendable {
    public struct Evidence: Codable, Equatable, Identifiable, Sendable {
        /// `site`, `controller`, `virtual_controller`, `ticket`, `cell`, `conversation` or `memory_page`.
        public let evidenceKind: String?
        public let evidenceId: String?
        public let evidenceLabel: String?
        public var id: String { "\(evidenceKind ?? "")|\(evidenceId ?? "")" }

        public init(evidenceKind: String?, evidenceId: String?, evidenceLabel: String?) {
            self.evidenceKind = evidenceKind
            self.evidenceId = evidenceId
            self.evidenceLabel = evidenceLabel
        }

        /// Only a site, a controller, a virtual controller and a conversation have a page of their own; a ticket and a memory page have none.
        public var isLinkable: Bool {
            guard let evidenceId, !evidenceId.isEmpty else { return false }
            return ["site", "controller", "virtual_controller", "conversation"].contains(evidenceKind ?? "")
        }
    }

    /// `catalog:<key>` until it is answered, then a row id.
    public let id: String
    public let ideaKind: String?
    public let catalogKey: String?
    public let headline: String?
    public let body: String?
    public let openingRequest: String?
    public let neededToolNames: [String]?
    /// `open`, `started`, `done`, `dismissed` or `expired`.
    public let ideaStatus: String?
    public let rank: Int?
    public let expiresAt: String?
    public let evidence: [Evidence]?

    public init(
        id: String, headline: String? = nil, body: String? = nil, ideaKind: String? = "found", ideaStatus: String? = "open", rank: Int? = nil,
        openingRequest: String? = nil, evidence: [Evidence]? = nil, neededToolNames: [String]? = nil, catalogKey: String? = nil, expiresAt: String? = nil
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.ideaKind = ideaKind
        self.ideaStatus = ideaStatus
        self.rank = rank
        self.openingRequest = openingRequest
        self.evidence = evidence
        self.neededToolNames = neededToolNames
        self.catalogKey = catalogKey
        self.expiresAt = expiresAt
    }

    public var isOpen: Bool { (ideaStatus ?? "open") == "open" }
}

/// AgentBackgroundSetting is the organization's switches for goals, found ideas and speaking first.
public struct AgentBackgroundSetting: Codable, Equatable, Sendable {
    public let organizationId: String?
    public let areGoalsEnabled: Bool?
    public let areFoundIdeasEnabled: Bool?
    public let isSpeakFirstEnabled: Bool?
    public let canManageOrganization: Bool?
}

extension Documents {
    static let goalFields = """
        id organizationId organizationName userId conversationId title description goalState statusLine waitingQuestion nextCheckAt lastCheckAt
        checkIntervalMinutes endedAt turnCount todayTurnCount createdAt
        """

    static let ideaFields = """
        id ideaKind catalogKey headline body openingRequest neededToolNames ideaStatus rank expiresAt evidence { evidenceKind evidenceId evidenceLabel }
        """

    static let backgroundSettingFields = "organizationId areGoalsEnabled areFoundIdeasEnabled isSpeakFirstEnabled canManageOrganization"

    public static let listGoals = """
        query ListGoals($shouldIncludeOthers: Boolean, $goalStates: [GoalState], $options: ListOptionsInput) {
          ListGoals(shouldIncludeOthers: $shouldIncludeOthers, goalStates: $goalStates, options: $options) {
            goals { \(goalFields) }
            meta { totalCount }
          }
        }
        """

    public static let getGoal = """
        query GetGoal($goalId: String) { GetGoal(goalId: $goalId) { \(goalFields) } }
        """

    public static let startGoal = """
        mutation StartGoal($title: String, $description: String, $checkIntervalMinutes: Int) {
          StartGoal(title: $title, description: $description, checkIntervalMinutes: $checkIntervalMinutes) { \(goalFields) }
        }
        """

    public static let tellGoal = """
        mutation TellGoal($goalId: String, $text: String) { TellGoal(goalId: $goalId, text: $text) { \(goalFields) } }
        """

    public static let markGoalMet = """
        mutation MarkGoalMet($goalId: String, $statusLine: String) { MarkGoalMet(goalId: $goalId, statusLine: $statusLine) { \(goalFields) } }
        """

    public static let stopGoal = """
        mutation StopGoal($goalId: String) { StopGoal(goalId: $goalId) { \(goalFields) } }
        """

    public static let reopenGoal = """
        mutation ReopenGoal($goalId: String) { ReopenGoal(goalId: $goalId) { \(goalFields) } }
        """

    public static let listGoalActivities = """
        query ListGoalActivities($goalId: String, $limit: Int64) { ListGoalActivities(goalId: $goalId, limit: $limit) { id goalId activityText createdAt } }
        """

    public static let listGoalTurns = """
        query ListGoalTurns($goalId: String, $shouldIncludeOthers: Boolean, $options: ListOptionsInput) {
          ListAgentActivity(goalId: $goalId, shouldIncludeOthers: $shouldIncludeOthers, options: $options) {
            activities { \(activityFields) }
            meta { totalCount }
          }
        }
        """

    public static let listIdeas = """
        query ListIdeas($ideaStatuses: [IdeaStatus]) { ListIdeas(ideaStatuses: $ideaStatuses) { ideas { \(ideaFields) } } }
        """

    public static let startIdea = """
        mutation StartIdea($ideaId: String) { StartIdea(ideaId: $ideaId) { draftRequest idea { \(ideaFields) } } }
        """

    public static let startGoalFromIdea = """
        mutation StartGoalFromIdea($ideaId: String) { StartGoalFromIdea(ideaId: $ideaId) { goal { \(goalFields) } idea { \(ideaFields) } } }
        """

    public static let dismissIdea = """
        mutation DismissIdea($ideaId: String) { DismissIdea(ideaId: $ideaId) { \(ideaFields) } }
        """

    public static let finishIdea = """
        mutation FinishIdea($ideaId: String) { FinishIdea(ideaId: $ideaId) { \(ideaFields) } }
        """

    public static let getAgentBackgroundSetting = """
        query GetAgentBackgroundSetting($organizationId: String) {
          GetAgentBackgroundSetting(organizationId: $organizationId) { \(backgroundSettingFields) }
        }
        """

    public static let setAgentBackgroundSetting = """
        mutation SetAgentBackgroundSetting($areGoalsEnabled: Boolean, $areFoundIdeasEnabled: Boolean, $isSpeakFirstEnabled: Boolean) {
          SetAgentBackgroundSetting(
            areGoalsEnabled: $areGoalsEnabled, areFoundIdeasEnabled: $areFoundIdeasEnabled, isSpeakFirstEnabled: $isSpeakFirstEnabled
          ) { \(backgroundSettingFields) }
        }
        """

    static var goalDocuments: [String] {
        [
            listGoals, getGoal, startGoal, tellGoal, markGoalMet, stopGoal, reopenGoal, listGoalActivities, listGoalTurns, listIdeas, startIdea,
            startGoalFromIdea, dismissIdea, finishIdea, getAgentBackgroundSetting, setAgentBackgroundSetting,
        ]
    }
}

extension Connection {
    /// The person's goals; with `includeOthers` an administrator also gets the organization's.
    public func goals(includeOthers: Bool = false, states: [GoalState]? = nil) async throws -> [Goal] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let goals: [Goal]? }
            let ListGoals: List?
        }
        var variables: [String: JSONValue] = ["shouldIncludeOthers": .bool(includeOthers), "options": .object(["first": .number(100)])]
        if let states { variables["goalStates"] = .array(states.map { .string($0.rawValue) }) }
        return try await execute(Documents.listGoals, variables: variables, as: Answer.self).ListGoals?.goals ?? []
    }

    public func goal(id: String) async throws -> Goal {
        struct Answer: Decodable, Sendable { let GetGoal: Goal }
        return try await execute(Documents.getGoal, variables: ["goalId": .string(id)], as: Answer.self).GetGoal
    }

    @discardableResult
    public func startGoal(title: String, description: String, checkIntervalMinutes: Int) async throws -> Goal {
        struct Answer: Decodable, Sendable { let StartGoal: Goal }
        return try await execute(
            Documents.startGoal,
            variables: ["title": .string(title), "description": .string(description), "checkIntervalMinutes": .number(Double(checkIntervalMinutes))],
            as: Answer.self
        ).StartGoal
    }

    /// Tells the assistant something about the goal, such as the answer to what blocks it.
    @discardableResult
    public func tellGoal(id: String, text: String) async throws -> Goal {
        struct Answer: Decodable, Sendable { let TellGoal: Goal }
        return try await execute(Documents.tellGoal, variables: ["goalId": .string(id), "text": .string(text)], as: Answer.self).TellGoal
    }

    @discardableResult
    public func markGoalMet(id: String, statusLine: String) async throws -> Goal {
        struct Answer: Decodable, Sendable { let MarkGoalMet: Goal }
        return try await execute(Documents.markGoalMet, variables: ["goalId": .string(id), "statusLine": .string(statusLine)], as: Answer.self).MarkGoalMet
    }

    @discardableResult
    public func stopGoal(id: String) async throws -> Goal {
        struct Answer: Decodable, Sendable { let StopGoal: Goal }
        return try await execute(Documents.stopGoal, variables: ["goalId": .string(id)], as: Answer.self).StopGoal
    }

    @discardableResult
    public func reopenGoal(id: String) async throws -> Goal {
        struct Answer: Decodable, Sendable { let ReopenGoal: Goal }
        return try await execute(Documents.reopenGoal, variables: ["goalId": .string(id)], as: Answer.self).ReopenGoal
    }

    public func goalActivities(id: String, limit: Int = 50) async throws -> [GoalActivity] {
        struct Answer: Decodable, Sendable { let ListGoalActivities: [GoalActivity]? }
        return try await execute(Documents.listGoalActivities, variables: ["goalId": .string(id), "limit": .number(Double(limit))], as: Answer.self)
            .ListGoalActivities ?? []
    }

    /// The turns the assistant took for a goal, newest first.
    public func goalTurns(id: String, includeOthers: Bool = false) async throws -> [AgentActivity] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let activities: [AgentActivity]? }
            let ListAgentActivity: List?
        }
        return try await execute(
            Documents.listGoalTurns,
            variables: ["goalId": .string(id), "shouldIncludeOthers": .bool(includeOthers), "options": .object(["first": .number(50)])], as: Answer.self
        ).ListAgentActivity?.activities ?? []
    }

    /// What is on offer, or with statuses the earlier ones.
    public func ideas(statuses: [String]? = nil) async throws -> [Idea] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let ideas: [Idea]? }
            let ListIdeas: List?
        }
        var variables: [String: JSONValue] = [:]
        if let statuses { variables["ideaStatuses"] = .array(statuses.map { .string($0) }) }
        return try await execute(Documents.listIdeas, variables: variables, as: Answer.self).ListIdeas?.ideas?.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) } ?? []
    }

    /// Starts an idea: the request to put in a new conversation's composer. Nothing is sent.
    public func startIdea(id: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Started: Decodable, Sendable { let draftRequest: String? }
            let StartIdea: Started
        }
        return try await execute(Documents.startIdea, variables: ["ideaId": .string(id)], as: Answer.self).StartIdea.draftRequest ?? ""
    }

    public func startGoalFromIdea(id: String) async throws -> Goal {
        struct Answer: Decodable, Sendable {
            struct Started: Decodable, Sendable { let goal: Goal }
            let StartGoalFromIdea: Started
        }
        return try await execute(Documents.startGoalFromIdea, variables: ["ideaId": .string(id)], as: Answer.self).StartGoalFromIdea.goal
    }

    public func dismissIdea(id: String) async throws {
        _ = try await execute(Documents.dismissIdea, variables: ["ideaId": .string(id)], as: JSONValue.self)
    }

    public func finishIdea(id: String) async throws {
        _ = try await execute(Documents.finishIdea, variables: ["ideaId": .string(id)], as: JSONValue.self)
    }

    public func backgroundSetting() async throws -> AgentBackgroundSetting {
        struct Answer: Decodable, Sendable { let GetAgentBackgroundSetting: AgentBackgroundSetting }
        return try await execute(Documents.getAgentBackgroundSetting, as: Answer.self).GetAgentBackgroundSetting
    }

    /// Leaving a switch out keeps it as it is.
    @discardableResult
    public func setBackgroundSetting(areGoalsEnabled: Bool? = nil, areFoundIdeasEnabled: Bool? = nil, isSpeakFirstEnabled: Bool? = nil) async throws -> AgentBackgroundSetting {
        struct Answer: Decodable, Sendable { let SetAgentBackgroundSetting: AgentBackgroundSetting }
        var variables: [String: JSONValue] = [:]
        if let areGoalsEnabled { variables["areGoalsEnabled"] = .bool(areGoalsEnabled) }
        if let areFoundIdeasEnabled { variables["areFoundIdeasEnabled"] = .bool(areFoundIdeasEnabled) }
        if let isSpeakFirstEnabled { variables["isSpeakFirstEnabled"] = .bool(isSpeakFirstEnabled) }
        return try await execute(Documents.setAgentBackgroundSetting, variables: variables, as: Answer.self).SetAgentBackgroundSetting
    }
}
