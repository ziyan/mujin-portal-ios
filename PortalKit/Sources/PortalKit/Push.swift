import Foundation

/// PushEnvironment is which of Apple's two push services issued the phone's
/// token. A token sent to the other service is rejected by Apple, and the
/// server then deletes it, so the build decides it once: a build run from
/// Xcode gets a sandbox token, TestFlight and the App Store a production one.
public enum PushEnvironment: String, Sendable {
    case sandbox
    case production

    /// The value the build put in the Info.plist (`PortalPushEnvironment`).
    /// A build that says nothing is a store build.
    public static var current: PushEnvironment {
        PushEnvironment(configured: Bundle.main.object(forInfoDictionaryKey: "PortalPushEnvironment") as? String)
    }

    public init(configured: String?) {
        self = PushEnvironment(rawValue: (configured ?? "").trimmingCharacters(in: .whitespaces).lowercased()) ?? .production
    }
}

/// PushCategory names the notification categories and their buttons. The
/// server sends the category in `aps.category`; the notification service
/// extension registers one category per question, with a button per choice.
public enum PushCategory {
    public static let approval = "PORTAL_APPROVAL"
    public static let question = "PORTAL_QUESTION"
    public static let reply = "PORTAL_REPLY"

    public static let approveAction = "PORTAL_APPROVE"
    public static let denyAction = "PORTAL_DENY"
    public static let replyAction = "PORTAL_REPLY_TEXT"
    /// The button for choice `index` of a question: `PORTAL_CHOICE_0`.
    public static let choiceActionPrefix = "PORTAL_CHOICE_"

    /// A question's choices as buttons: at most four, each at most 40 characters.
    public static let maximumChoices = 4
    public static let maximumChoiceLength = 40

    public static func choiceAction(index: Int) -> String { "\(choiceActionPrefix)\(index)" }

    public static func choiceIndex(ofAction identifier: String) -> Int? {
        guard identifier.hasPrefix(choiceActionPrefix) else { return nil }
        return Int(identifier.dropFirst(choiceActionPrefix.count))
    }

    /// The category one question registers, so its buttons are its own choices.
    public static func questionCategory(interactionId: String) -> String { "\(question).\(interactionId)" }
}

/// PushPayload is the `portal` object of a push notification: who it is for,
/// what it is about and what it can be answered with. Several accounts can
/// share a phone, so `userId` decides whose connection acts on it.
public struct PushPayload: Equatable, Sendable {
    public let userId: String
    public let organizationId: String?
    public let kind: String
    public let notificationId: String?
    public let conversationId: String?
    public let interactionId: String?
    /// `question` or `approval` for a card that waits.
    public let waitingKind: String?
    public let chatId: String?
    public let goalId: String?
    public let jobId: String?
    public let choices: [String]
    /// True for the passive push that replaces a card answered elsewhere.
    public let isAnswered: Bool
    /// The notification's thread, so one conversation's notifications stack.
    public let threadId: String?

    public init(
        userId: String, organizationId: String? = nil, kind: String, notificationId: String? = nil, conversationId: String? = nil,
        interactionId: String? = nil, waitingKind: String? = nil, chatId: String? = nil, goalId: String? = nil, jobId: String? = nil,
        choices: [String] = [], isAnswered: Bool = false, threadId: String? = nil
    ) {
        self.userId = userId
        self.organizationId = organizationId
        self.kind = kind
        self.notificationId = notificationId
        self.conversationId = conversationId
        self.interactionId = interactionId
        self.waitingKind = waitingKind
        self.chatId = chatId
        self.goalId = goalId
        self.jobId = jobId
        self.choices = choices
        self.isAnswered = isAnswered
        self.threadId = threadId
    }

    /// Reads a notification's `userInfo`. Nil when it is not one of Portal's.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let portal = userInfo["portal"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            let value = portal[key]
            if let string = value as? String { return string.isEmpty ? nil : string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        guard let userId = text("userId"), let kind = text("kind") else { return nil }
        var choices: [String] = []
        if let list = portal["choices"] as? [String] {
            choices = list
        } else if let encoded = portal["choices"] as? String, let data = encoded.data(using: .utf8),
            let list = try? JSONDecoder().decode([String].self, from: data)
        {
            choices = list
        }
        self.init(
            userId: userId, organizationId: text("organizationId"), kind: kind, notificationId: text("notificationId"),
            conversationId: text("conversationId"), interactionId: text("interactionId"), waitingKind: text("waitingKind"),
            chatId: text("chatId"), goalId: text("goalId"), jobId: text("jobId"),
            choices: Self.buttonChoices(choices), isAnswered: text("isAnswered") == "true" || (portal["isAnswered"] as? Bool) == true,
            threadId: ((userInfo["aps"] as? [String: Any])?["thread-id"] as? String))
    }

    /// The choices that become buttons: non-empty, clipped, at most four.
    public static func buttonChoices(_ choices: [String]) -> [String] {
        let usable = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return usable.prefix(PushCategory.maximumChoices).map {
            $0.count > PushCategory.maximumChoiceLength ? String($0.prefix(PushCategory.maximumChoiceLength - 1)) + "\u{2026}" : $0
        }
    }

    public var isApproval: Bool { kind == "agent_waiting" && waitingKind == "approval" && interactionId != nil }
    public var isQuestion: Bool { kind == "agent_waiting" && waitingKind == "question" && interactionId != nil }

    /// The category a notification should show with. A question gets its own,
    /// registered by the extension with its choices; the others are fixed.
    public var categoryIdentifier: String? {
        if isApproval { return PushCategory.approval }
        if isQuestion, let interactionId { return PushCategory.questionCategory(interactionId: interactionId) }
        if kind == "agent_message" || kind == "chat_message", conversationId != nil { return PushCategory.reply }
        return nil
    }

    /// The notification's thread: its own, else the conversation or chat it belongs to.
    public var resolvedThreadId: String? {
        if let threadId, !threadId.isEmpty { return threadId }
        return conversationId ?? chatId
    }

    /// Where tapping the notification goes.
    public var route: PushRoute {
        switch kind {
        case "agent_waiting", "agent_message":
            if let conversationId { return .conversation(id: conversationId) }
            return .notifications
        case "chat_message":
            if let conversationId { return .chat(conversationId: conversationId) }
            return .notifications
        case "agent_goal_needs_you":
            if let goalId { return .goal(id: goalId) }
            return .notifications
        case "agent_job_failed": return .automations
        default: return .notifications
        }
    }

    /// What a tapped button does. Nil for a button this payload does not offer.
    public func action(forButton identifier: String, text: String?) -> PushAction? {
        let typed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch identifier {
        case PushCategory.approveAction:
            return interactionId.map { .resolveApproval(id: $0, isApproved: true) }
        case PushCategory.denyAction:
            return interactionId.map { .resolveApproval(id: $0, isApproved: false) }
        case PushCategory.replyAction:
            guard !typed.isEmpty else { return nil }
            if isQuestion, let interactionId { return .answerQuestion(id: interactionId, answer: typed) }
            if let conversationId { return .reply(conversationId: conversationId, text: typed) }
            return nil
        default:
            if let index = PushCategory.choiceIndex(ofAction: identifier), choices.indices.contains(index), let interactionId, isQuestion {
                return .answerQuestion(id: interactionId, answer: choices[index])
            }
            return nil
        }
    }
}

/// PushRoute is a place in the app a notification opens.
public enum PushRoute: Equatable, Sendable {
    case conversation(id: String)
    case chat(conversationId: String)
    case goal(id: String)
    case automations
    case notifications
}

/// PushAction is what a notification's button asks the server to do.
public enum PushAction: Equatable, Sendable {
    case resolveApproval(id: String, isApproved: Bool)
    case answerQuestion(id: String, answer: String)
    case reply(conversationId: String, text: String)
}

extension Documents {
    public static let registerPushDevice = """
        mutation RegisterPushDevice($deviceToken: String, $environment: PushEnvironment, $deviceName: String, $appVersion: String) {
          RegisterPushDevice(deviceToken: $deviceToken, environment: $environment, deviceName: $deviceName, appVersion: $appVersion) {
            pushDevice { id pushEnvironment deviceName appVersion }
          }
        }
        """

    public static let unregisterPushDevice = """
        mutation UnregisterPushDevice($deviceToken: String) { UnregisterPushDevice(deviceToken: $deviceToken) { isRemoved } }
        """

    static var pushDocuments: [String] { [registerPushDevice, unregisterPushDevice] }
}

extension Connection {
    /// Tells the server this phone's token, at every launch and whenever the
    /// token changes. It is idempotent per person and token.
    public func registerPushDevice(deviceToken: String, environment: PushEnvironment, deviceName: String, appVersion: String) async throws {
        _ = try await execute(
            Documents.registerPushDevice,
            variables: [
                "deviceToken": .string(deviceToken), "environment": .string(environment.rawValue), "deviceName": .string(deviceName),
                "appVersion": .string(appVersion),
            ], as: JSONValue.self)
    }

    /// Stops this account's pushes to this phone while the other accounts
    /// on it keep theirs.
    public func unregisterPushDevice(deviceToken: String) async throws {
        _ = try await execute(Documents.unregisterPushDevice, variables: ["deviceToken": .string(deviceToken)], as: JSONValue.self)
    }

    /// Does what a notification's button asked.
    public func perform(_ action: PushAction) async throws {
        switch action {
        case .resolveApproval(let id, let isApproved): try await resolveToolApproval(id: id, isApproved: isApproved)
        case .answerQuestion(let id, let answer): try await answerQuestion(id: id, answer: answer)
        case .reply(let conversationId, let text): try await sendMessage(conversationId: conversationId, text: text)
        }
    }
}
