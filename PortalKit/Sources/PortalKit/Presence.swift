import Foundation

/// PendingSpeakFirst is a conversation the assistant started with the person,
/// for ten minutes after it did. The presence report answers with it.
public struct PendingSpeakFirst: Codable, Equatable, Sendable {
    public let speakFirstId: String
    public let conversationId: String
    /// `onboarding`, `goal_needs_you`, `memory_check` or `idea`.
    public let speakFirstReason: String?
    public let startedAt: String?

    public init(speakFirstId: String, conversationId: String, speakFirstReason: String? = nil, startedAt: String? = nil) {
        self.speakFirstId = speakFirstId
        self.conversationId = conversationId
        self.speakFirstReason = speakFirstReason
        self.startedAt = startedAt
    }
}

/// PresenceRules holds the clock of the presence contract: a report counts
/// for two minutes on the server, so a visible app reports every minute.
public enum PresenceRules {
    public static let source = "app"
    public static let reportInterval: TimeInterval = 60
    /// The most idle seconds worth sending; the server only needs to know the person is not touching the phone.
    public static let maximumIdleSeconds = 3_600

    public static func idleSeconds(since lastTouch: Date, now: Date) -> Int {
        min(maximumIdleSeconds, max(0, Int(now.timeIntervalSince(lastTouch))))
    }
}

/// SpeakFirstMemory remembers the last conversation the assistant started
/// that this phone has already opened, so it opens each one once.
public struct SpeakFirstMemory: Sendable {
    static let key = "lastHandledSpeakFirstId"
    private let defaultsProvider: @Sendable () -> UserDefaults

    public init(defaults: @escaping @Sendable () -> UserDefaults = { AppGroup.defaults }) {
        self.defaultsProvider = defaults
    }

    public var lastHandledId: String? { defaultsProvider().string(forKey: Self.key) }

    /// Whether the person has not been taken to this one yet.
    public func isNew(_ pending: PendingSpeakFirst) -> Bool { pending.speakFirstId != lastHandledId }

    public func markHandled(_ pending: PendingSpeakFirst) { defaultsProvider().set(pending.speakFirstId, forKey: Self.key) }
}

/// AgentSpeakFirstSetting is the person's choices about the assistant starting a conversation.
public struct AgentSpeakFirstSetting: Codable, Equatable, Sendable {
    public struct Last: Codable, Equatable, Sendable {
        public let id: String?
        public let speakFirstReason: String?
        public let speakFirstStatus: String?
        public let startedAt: String?
        public let conversationId: String?
    }
    public let organizationId: String?
    public let userId: String?
    public let isEnabledForOrganization: Bool?
    public let isEnabledForUser: Bool?
    public let snoozedUntil: String?
    public let disabledReasons: [String]?
    public let canManageOrganization: Bool?
    public let lastSpeakFirst: Last?

    public var isSnoozed: Bool {
        guard let until = PortalDate.parse(snoozedUntil) else { return false }
        return until > Date()
    }

    /// Nothing is ever sent while the organization has it off, whatever the person chose.
    public var isOrganizationOff: Bool { isEnabledForOrganization == false }

    public func isReasonEnabled(_ reason: String) -> Bool { !(disabledReasons ?? []).contains(reason) }

    /// The reasons a person can switch; onboarding has no switch of its own.
    public static let switchableReasons = ["goal_needs_you", "memory_check", "idea"]
}

extension Documents {
    static let speakFirstSettingFields = """
        organizationId userId isEnabledForOrganization isEnabledForUser snoozedUntil disabledReasons canManageOrganization
        lastSpeakFirst { id speakFirstReason speakFirstStatus startedAt conversationId }
        """

    public static let reportAgentPresence = """
        mutation ReportAgentPresence($isVisible: Boolean, $idleSeconds: Int, $reporterId: String, $source: String) {
          ReportAgentPresence(isVisible: $isVisible, idleSeconds: $idleSeconds, reporterId: $reporterId, source: $source) {
            pendingSpeakFirst { speakFirstId conversationId speakFirstReason startedAt }
          }
        }
        """

    public static let getAgentSpeakFirstSetting = """
        query GetAgentSpeakFirstSetting { GetAgentSpeakFirstSetting { \(speakFirstSettingFields) } }
        """

    public static let setAgentSpeakFirst = """
        mutation SetAgentSpeakFirst($isEnabled: Boolean) { SetAgentSpeakFirst(isEnabled: $isEnabled) { \(speakFirstSettingFields) } }
        """

    public static let snoozeAgentSpeakFirst = """
        mutation SnoozeAgentSpeakFirst($isSnoozed: Boolean) { SnoozeAgentSpeakFirst(isSnoozed: $isSnoozed) { \(speakFirstSettingFields) } }
        """

    public static let setAgentSpeakFirstReason = """
        mutation SetAgentSpeakFirstReason($speakFirstReason: SpeakFirstReason, $isEnabled: Boolean) {
          SetAgentSpeakFirstReason(speakFirstReason: $speakFirstReason, isEnabled: $isEnabled) { \(speakFirstSettingFields) }
        }
        """

    static var presenceDocuments: [String] {
        [reportAgentPresence, getAgentSpeakFirstSetting, setAgentSpeakFirst, snoozeAgentSpeakFirst, setAgentSpeakFirstReason]
    }
}

extension Connection {
    /// Tells the server whether the app is in front. While it is, the
    /// assistant does not push what the person is looking at. The answer
    /// carries a conversation the assistant just started, when there is one.
    @discardableResult
    public func reportPresence(isVisible: Bool, idleSeconds: Int, reporterId: String) async throws -> PendingSpeakFirst? {
        struct Answer: Decodable, Sendable {
            struct Receipt: Decodable, Sendable { let pendingSpeakFirst: PendingSpeakFirst? }
            let ReportAgentPresence: Receipt?
        }
        let answer = try await execute(
            Documents.reportAgentPresence,
            variables: [
                "isVisible": .bool(isVisible), "idleSeconds": .number(Double(idleSeconds)), "reporterId": .string(reporterId),
                "source": .string(PresenceRules.source),
            ], as: Answer.self)
        return answer.ReportAgentPresence?.pendingSpeakFirst
    }

    public func speakFirstSetting() async throws -> AgentSpeakFirstSetting {
        struct Answer: Decodable, Sendable { let GetAgentSpeakFirstSetting: AgentSpeakFirstSetting }
        return try await execute(Documents.getAgentSpeakFirstSetting, as: Answer.self).GetAgentSpeakFirstSetting
    }

    @discardableResult
    public func setSpeakFirst(isEnabled: Bool) async throws -> AgentSpeakFirstSetting {
        struct Answer: Decodable, Sendable { let SetAgentSpeakFirst: AgentSpeakFirstSetting }
        return try await execute(Documents.setAgentSpeakFirst, variables: ["isEnabled": .bool(isEnabled)], as: Answer.self).SetAgentSpeakFirst
    }

    /// Pauses the assistant speaking first for 24 hours, or resumes it.
    @discardableResult
    public func snoozeSpeakFirst(isSnoozed: Bool) async throws -> AgentSpeakFirstSetting {
        struct Answer: Decodable, Sendable { let SnoozeAgentSpeakFirst: AgentSpeakFirstSetting }
        return try await execute(Documents.snoozeAgentSpeakFirst, variables: ["isSnoozed": .bool(isSnoozed)], as: Answer.self).SnoozeAgentSpeakFirst
    }

    @discardableResult
    public func setSpeakFirstReason(_ reason: String, isEnabled: Bool) async throws -> AgentSpeakFirstSetting {
        struct Answer: Decodable, Sendable { let SetAgentSpeakFirstReason: AgentSpeakFirstSetting }
        return try await execute(
            Documents.setAgentSpeakFirstReason, variables: ["speakFirstReason": .string(reason), "isEnabled": .bool(isEnabled)], as: Answer.self
        ).SetAgentSpeakFirstReason
    }

    /// "Stop these" under the first message: the reason's own switch, or the
    /// whole feature for onboarding, which has none.
    @discardableResult
    public func stopSpeakingFirst(reason: String) async throws -> AgentSpeakFirstSetting {
        if AgentSpeakFirstSetting.switchableReasons.contains(reason) { return try await setSpeakFirstReason(reason, isEnabled: false) }
        return try await setSpeakFirst(isEnabled: false)
    }
}

/// ReporterIdentity is the random id this install reports presence under, so
/// the server can tell two phones of one person apart. It is kept in the
/// keychain, and in the app group's settings where there is no keychain.
public enum ReporterIdentity {
    static let name = "presence-reporter-id"

    public static func current() -> String {
        #if canImport(Security)
            if let data = try? Keychain.read(name), let stored = String(data: data, encoding: .utf8), !stored.isEmpty { return stored }
            let keychainId = UUID().uuidString.lowercased()
            if (try? Keychain.write(Data(keychainId.utf8), as: name)) != nil { return keychainId }
        #endif
        let defaults = AppGroup.defaults
        if let stored = defaults.string(forKey: name), !stored.isEmpty { return stored }
        let defaultsId = UUID().uuidString.lowercased()
        defaults.set(defaultsId, forKey: name)
        return defaultsId
    }
}
