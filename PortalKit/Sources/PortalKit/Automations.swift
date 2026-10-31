import Foundation

/// ScheduleOccurrence is one time the assistant is due to do something.
public struct ScheduleOccurrence: Codable, Equatable, Identifiable, Sendable {
    /// `job` or `goal_check_in`. A kind the app does not know is drawn as a plain entry.
    public let occurrenceKind: String?
    public let occursAt: String?
    public let subjectId: String?
    public let title: String?
    /// `recurring`, `oneshot` or `monitor`.
    public let jobType: String?
    public let organizationId: String?
    public let userId: String?
    public let timeZoneName: String?
    /// Empty until the job has run once.
    public let conversationId: String?

    public var id: String { "\(subjectId ?? "")|\(occursAt ?? "")|\(occurrenceKind ?? "")" }
    public var date: Date? { PortalDate.parse(occursAt) }

    public init(
        occurrenceKind: String? = "job", occursAt: String?, subjectId: String?, title: String?, jobType: String? = nil,
        organizationId: String? = nil, userId: String? = nil, timeZoneName: String? = nil, conversationId: String? = nil
    ) {
        self.occurrenceKind = occurrenceKind
        self.occursAt = occursAt
        self.subjectId = subjectId
        self.title = title
        self.jobType = jobType
        self.organizationId = organizationId
        self.userId = userId
        self.timeZoneName = timeZoneName
        self.conversationId = conversationId
    }
}

/// ScheduleDay is the occurrences that fall on one calendar day of the device.
public struct ScheduleDay: Equatable, Identifiable, Sendable {
    public let day: Date
    public let occurrences: [ScheduleOccurrence]
    public var id: Date { day }
}

public enum AgentSchedule {
    /// Groups occurrences by the device's calendar day, soonest first.
    /// `occursAt` is an instant, so the day depends on the calendar given.
    public static func groupedByDay(_ occurrences: [ScheduleOccurrence], calendar: Calendar = .current) -> [ScheduleDay] {
        let dated = occurrences.compactMap { occurrence in occurrence.date.map { ($0, occurrence) } }.sorted { $0.0 < $1.0 }
        var order: [Date] = []
        var byDay: [Date: [ScheduleOccurrence]] = [:]
        for (date, occurrence) in dated {
            let day = calendar.startOfDay(for: date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(occurrence)
        }
        return order.map { ScheduleDay(day: $0, occurrences: byDay[$0] ?? []) }
    }
}

/// AgentActivity is one run the assistant did on its own: a scheduled job,
/// a monitor, or background work.
public struct AgentActivity: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// `scheduled_job`, `monitor` or `background_work`.
    public let activityKind: String?
    /// `queued`, `running`, `succeeded`, `failed` or `cancelled`.
    public let activityStatus: String?
    public let title: String?
    public let organizationId: String?
    public let organizationName: String?
    public let userId: String?
    public let startedAt: String?
    public let endedAt: String?
    public let tokenCount: Int64?
    public let costMicroMinorUnits: Int64?
    public let costCurrency: String?
    public let conversationId: String?
    public let answerMessageId: String?
    public let jobId: String?
    public let backgroundWorkId: String?
    public let errorMessage: String?

    public var isInProgress: Bool { activityStatus == "queued" || activityStatus == "running" }
    public var hasFailed: Bool { activityStatus == "failed" }
    public var hasTranscript: Bool { !(conversationId ?? "").isEmpty }
    public var startedDate: Date? { PortalDate.parse(startedAt) }

    /// What the run cost, or nil when it was not priced.
    public var costText: String? { CostFormat.string(microMinorUnits: costMicroMinorUnits ?? 0, currency: costCurrency ?? "") }
}

extension Array where Element == AgentActivity {
    /// Whether any run is still going, which is when the list is polled.
    public var needsPolling: Bool { contains(where: \.isInProgress) }
}

/// BackgroundWork is work the assistant started and let run on its own.
public struct BackgroundWork: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let organizationId: String?
    public let userId: String?
    public let parentConversationId: String?
    public let parentMessageId: String?
    public let childConversationId: String?
    public let title: String?
    public let purpose: String?
    /// `queued`, `running`, `done`, `failed` or `stopped`.
    public let workState: String?
    public let resultText: String?
    public let errorMessage: String?
    public let tokenCount: Int64?
    public let costMicroMinorUnits: Int64?
    public let costCurrency: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let wokenAt: String?
    public let wakeNote: String?
    public let createdAt: String?

    public var isInProgress: Bool { workState == "queued" || workState == "running" }
    public var hasFailed: Bool { workState == "failed" }
    public var costText: String? { CostFormat.string(microMinorUnits: costMicroMinorUnits ?? 0, currency: costCurrency ?? "") }

    /// "Report" shows the result, or the error of a failure.
    public var reportText: String? {
        let text = hasFailed ? errorMessage : resultText
        return (text ?? "").isEmpty ? nil : text
    }
}

/// CostFormat writes what a run cost. Portal sends millionths of the
/// currency's minor unit; 0 means it was not priced.
public enum CostFormat {
    static func minorUnitDigits(_ currency: String) -> Int {
        switch currency.uppercased() {
        case "JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF", "XPF": 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND": 3
        default: 2
        }
    }

    /// The amount in whole currency units.
    public static func amount(microMinorUnits: Int64, currency: String) -> Double {
        Double(microMinorUnits) / pow(10, Double(6 + minorUnitDigits(currency)))
    }

    /// The cost as text, with four decimals below one unit of currency, or nil when unpriced.
    public static func string(microMinorUnits: Int64, currency: String, locale: Locale = .current) -> String? {
        guard microMinorUnits > 0, !currency.isEmpty else { return nil }
        let value = amount(microMinorUnits: microMinorUnits, currency: currency)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        let digits = value < 1 ? 4 : minorUnitDigits(currency)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value))
    }
}

extension Documents {
    static let activityFields = """
        id activityKind activityStatus title organizationId organizationName userId startedAt endedAt tokenCount costMicroMinorUnits
        costCurrency conversationId answerMessageId jobId backgroundWorkId errorMessage
        """

    static let backgroundWorkFields = """
        id organizationId userId parentConversationId parentMessageId childConversationId title purpose workState resultText errorMessage
        tokenCount costMicroMinorUnits costCurrency startedAt finishedAt wokenAt wakeNote createdAt
        """

    public static let listSchedule = """
        query ListAgentSchedule($dayCount: Int, $shouldIncludeOthers: Boolean, $organizationId: String) {
          ListAgentSchedule(dayCount: $dayCount, shouldIncludeOthers: $shouldIncludeOthers, organizationId: $organizationId) {
            occurrences { occurrenceKind occursAt subjectId title jobType organizationId userId timeZoneName conversationId }
            rangeStartedAt rangeEndedAt unreadableJobCount
          }
        }
        """

    public static let listActivity = """
        query ListAgentActivity($shouldIncludeOthers: Boolean, $organizationId: String, $options: ListOptionsInput) {
          ListAgentActivity(shouldIncludeOthers: $shouldIncludeOthers, organizationId: $organizationId, options: $options) {
            activities { \(activityFields) }
            meta { totalCount }
          }
        }
        """

    public static let listBackgroundWork = """
        query ListBackgroundWork(
          $conversationId: String, $shouldIncludeOthers: Boolean, $shouldIncludeFinished: Boolean, $organizationId: String, $options: ListOptionsInput
        ) {
          ListBackgroundWork(
            conversationId: $conversationId, shouldIncludeOthers: $shouldIncludeOthers, shouldIncludeFinished: $shouldIncludeFinished,
            organizationId: $organizationId, options: $options
          ) {
            backgroundWork { \(backgroundWorkFields) }
            meta { totalCount }
          }
        }
        """

    public static let stopBackgroundWork = """
        mutation StopBackgroundWork($id: String) {
          StopBackgroundWork(id: $id) { backgroundWork { \(backgroundWorkFields) } }
        }
        """

    static var automationDocuments: [String] { [listSchedule, listActivity, listBackgroundWork, stopBackgroundWork] }
}

extension Connection {
    /// What the assistant is due to do in the next `dayCount` days (at most 31), soonest first.
    public func schedule(dayCount: Int = 7, includeOthers: Bool = false, organizationId: String? = nil) async throws -> (occurrences: [ScheduleOccurrence], unreadableJobCount: Int) {
        struct Answer: Decodable, Sendable {
            struct Schedule: Decodable, Sendable {
                let occurrences: [ScheduleOccurrence]?
                let unreadableJobCount: Int?
            }
            let ListAgentSchedule: Schedule?
        }
        var variables: [String: JSONValue] = ["dayCount": .number(Double(min(max(dayCount, 1), 31))), "shouldIncludeOthers": .bool(includeOthers)]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        let schedule = try await execute(Documents.listSchedule, variables: variables, as: Answer.self).ListAgentSchedule
        return ((schedule?.occurrences ?? []).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }, schedule?.unreadableJobCount ?? 0)
    }

    /// The runs the assistant did on its own, newest first.
    public func activity(includeOthers: Bool = false, organizationId: String? = nil, first: Int = 50) async throws -> [AgentActivity] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let activities: [AgentActivity]? }
            let ListAgentActivity: List?
        }
        var variables: [String: JSONValue] = ["shouldIncludeOthers": .bool(includeOthers), "options": .object(["first": .number(Double(first))])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        return try await execute(Documents.listActivity, variables: variables, as: Answer.self).ListAgentActivity?.activities ?? []
    }

    /// Background work: queued and running, or finished too. With a
    /// conversation id it is what that conversation started.
    public func backgroundWork(
        conversationId: String? = nil, includeOthers: Bool = false, includeFinished: Bool = false, organizationId: String? = nil, first: Int = 50
    ) async throws -> [BackgroundWork] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let backgroundWork: [BackgroundWork]? }
            let ListBackgroundWork: List?
        }
        var variables: [String: JSONValue] = [
            "shouldIncludeOthers": .bool(includeOthers), "shouldIncludeFinished": .bool(includeFinished), "options": .object(["first": .number(Double(first))]),
        ]
        if let conversationId { variables["conversationId"] = .string(conversationId) }
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        return try await execute(Documents.listBackgroundWork, variables: variables, as: Answer.self).ListBackgroundWork?.backgroundWork ?? []
    }

    /// Stops background work. Only its owner may; anyone else gets not found.
    public func stopBackgroundWork(id: String) async throws {
        _ = try await execute(Documents.stopBackgroundWork, variables: ["id": .string(id)], as: JSONValue.self)
    }
}
