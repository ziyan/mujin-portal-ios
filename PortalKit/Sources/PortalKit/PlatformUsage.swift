import Foundation

/// UsageWindow is how far back usage is read, and how fine the server buckets it.
public enum UsageWindow: String, CaseIterable, Equatable, Hashable, Sendable {
    case lastDay
    case lastWeek
    case lastMonth

    /// The bucket size the server groups by: hours for a day, days for longer.
    public var intervalType: String { self == .lastDay ? "hour" : "day" }

    public var duration: TimeInterval {
        switch self {
        case .lastDay: return 86_400
        case .lastWeek: return 7 * 86_400
        case .lastMonth: return 30 * 86_400
        }
    }

    public func sinceMilliseconds(now: Date = Date()) -> Double { ((now.timeIntervalSince1970 - duration) * 1000).rounded() }
    public func untilMilliseconds(now: Date = Date()) -> Double { (now.timeIntervalSince1970 * 1000).rounded() }
}

/// ProviderUsageRow is the AI usage of one provider and model over one bucket of time.
public struct ProviderUsageRow: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let providerId: String?
    public let providerName: String?
    public let providerModelName: String?
    public let organizationId: String?
    public let userId: String?
    public let agentId: String?
    public let kind: String?
    public let startedAt: String?
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let cacheCreationTokens: Int?
    public let cacheReadTokens: Int?
    public let totalTokens: Int?
    public let requestCount: Int?

    public var tokenCount: Int { totalTokens ?? ((promptTokens ?? 0) + (completionTokens ?? 0)) }

    /// "Provider name, model", or whichever of the two is known.
    public var modelLabel: String {
        let parts = [providerName, providerModelName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown model" : parts.joined(separator: ", ")
    }
}

/// UsageLine is a total for one thing: a model, an organization or a controller.
public struct UsageLine: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let tokenCount: Int
    public let requestCount: Int
}

public struct ProviderUsageSummary: Equatable, Sendable {
    public let tokenCount: Int
    public let requestCount: Int
    public let promptTokenCount: Int
    public let completionTokenCount: Int
    /// Models, the heaviest first.
    public let byModel: [UsageLine]
    /// Organizations, the heaviest first. An organization with no known name is called "Unknown organization".
    public let byOrganization: [UsageLine]

    public init(rows: [ProviderUsageRow], organizationNames: [String: String] = [:]) {
        tokenCount = rows.reduce(0) { $0 + $1.tokenCount }
        requestCount = rows.reduce(0) { $0 + ($1.requestCount ?? 0) }
        promptTokenCount = rows.reduce(0) { $0 + ($1.promptTokens ?? 0) }
        completionTokenCount = rows.reduce(0) { $0 + ($1.completionTokens ?? 0) }
        byModel = Self.lines(rows, key: { "\($0.providerId ?? "")|\($0.providerModelName ?? "")" }, label: { $0.modelLabel })
        byOrganization = Self.lines(
            rows, key: { $0.organizationId ?? "" },
            label: { row in
                let name = row.organizationId.flatMap { organizationNames[$0] } ?? ""
                return name.isEmpty ? "Unknown organization" : name
            })
    }

    private static func lines(_ rows: [ProviderUsageRow], key: (ProviderUsageRow) -> String, label: (ProviderUsageRow) -> String) -> [UsageLine] {
        var tokens: [String: Int] = [:]
        var requests: [String: Int] = [:]
        var labels: [String: String] = [:]
        for row in rows {
            let identifier = key(row)
            tokens[identifier, default: 0] += row.tokenCount
            requests[identifier, default: 0] += row.requestCount ?? 0
            labels[identifier] = label(row)
        }
        return tokens.map { UsageLine(id: $0.key, label: labels[$0.key] ?? $0.key, tokenCount: $0.value, requestCount: requests[$0.key] ?? 0) }
            .sorted { $0.tokenCount != $1.tokenCount ? $0.tokenCount > $1.tokenCount : $0.label.localizedCompare($1.label) == .orderedAscending }
    }
}

/// ControllerUsageRow is the traffic and uptime of one controller over one bucket of time.
public struct ControllerUsageRow: Codable, Equatable, Hashable, Sendable {
    public let controllerId: String?
    public let controllerComment: String?
    public let startedAt: String?
    /// Bytes sent.
    public let sent: Int?
    /// Bytes received.
    public let received: Int?
    /// Seconds connected.
    public let up: Int?

    public var label: String {
        let comment = (controllerComment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.isEmpty ? (controllerId ?? "Unknown controller") : comment
    }
}

/// ControllerUsageLine is a controller's totals over the window.
public struct ControllerUsageLine: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let sentBytes: Int
    public let receivedBytes: Int
    public let connectedSeconds: Int
    public var totalBytes: Int { sentBytes + receivedBytes }
}

public enum ControllerUsageSummary {
    /// One line per controller, the heaviest traffic first.
    public static func lines(_ rows: [ControllerUsageRow]) -> [ControllerUsageLine] {
        var sent: [String: Int] = [:]
        var received: [String: Int] = [:]
        var connected: [String: Int] = [:]
        var labels: [String: String] = [:]
        for row in rows {
            let identifier = row.controllerId ?? row.label
            sent[identifier, default: 0] += row.sent ?? 0
            received[identifier, default: 0] += row.received ?? 0
            connected[identifier, default: 0] += row.up ?? 0
            labels[identifier] = row.label
        }
        return sent.keys.map {
            ControllerUsageLine(id: $0, label: labels[$0] ?? $0, sentBytes: sent[$0] ?? 0, receivedBytes: received[$0] ?? 0, connectedSeconds: connected[$0] ?? 0)
        }.sorted { $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.label.localizedCompare($1.label) == .orderedAscending }
    }
}

/// UsageFormat writes quantities the way the web's usage pages do.
public enum UsageFormat {
    /// "950", "12.3K", "4.5M", "1.2B".
    public static func tokens(_ count: Int) -> String {
        let value = Double(count)
        for (limit, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] where value >= limit {
            let scaled = value / limit
            return String(format: scaled >= 100 ? "%.0f%@" : "%.1f%@", scaled, suffix)
        }
        return String(count)
    }

    /// "0 B", "512 B", "1.5 KB", "3.2 GB".
    public static func bytes(_ count: Int) -> String {
        guard count > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var exponent = 0
        var value = Double(count)
        while value >= 1024, exponent < units.count - 1 {
            value /= 1024
            exponent += 1
        }
        return exponent == 0 ? "\(count) B" : String(format: "%.1f %@", value, units[exponent])
    }

    /// "45s", "12m 5s", "3h 20m", "2d 4h".
    public static func duration(seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}

extension Documents {
    public static let listProviderUsage = """
        query ListProviderUsage($organizationId: String, $intervalType: String, $sinceMillis: Int64, $untilMillis: Int64) {
          ListProviderUsage(organizationId: $organizationId, intervalType: $intervalType, sinceMillis: $sinceMillis, untilMillis: $untilMillis) {
            id providerId providerName providerModelName organizationId userId agentId kind startedAt
            promptTokens completionTokens cacheCreationTokens cacheReadTokens totalTokens requestCount
          }
        }
        """

    public static let listControllerUsageHistory = """
        query ListControllerUsageHistory($intervalType: IntervalType, $organizationId: String, $sinceMillis: Int64, $untilMillis: Int64) {
          ListControllerUsageHistory(intervalType: $intervalType, organizationId: $organizationId, sinceMillis: $sinceMillis, untilMillis: $untilMillis) {
            controllerId controllerComment startedAt sent received up
          }
        }
        """

    static var usageDocuments: [String] { [listProviderUsage, listControllerUsageHistory] }
}

extension Connection {
    /// AI usage over the window. `organizationId` narrows it to one organization; a person without the usage permission is always shown their own.
    public func providerUsage(window: UsageWindow, organizationId: String? = nil, now: Date = Date()) async throws -> [ProviderUsageRow] {
        struct Answer: Decodable, Sendable { let ListProviderUsage: [ProviderUsageRow?]? }
        var variables: [String: JSONValue] = [
            "intervalType": .string(window.intervalType), "sinceMillis": .number(window.sinceMilliseconds(now: now)),
            "untilMillis": .number(window.untilMilliseconds(now: now)),
        ]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        return try await execute(Documents.listProviderUsage, variables: variables, as: Answer.self).ListProviderUsage?.compactMap { $0 } ?? []
    }

    /// Traffic and uptime of every controller over the window, for a platform administrator.
    public func controllerUsage(window: UsageWindow, organizationId: String? = nil, now: Date = Date()) async throws -> [ControllerUsageRow] {
        struct Answer: Decodable, Sendable { let ListControllerUsageHistory: [ControllerUsageRow?]? }
        var variables: [String: JSONValue] = [
            "intervalType": .string(window == .lastDay ? "hour" : "day"), "sinceMillis": .number(window.sinceMilliseconds(now: now)),
            "untilMillis": .number(window.untilMilliseconds(now: now)),
        ]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        return try await execute(Documents.listControllerUsageHistory, variables: variables, as: Answer.self).ListControllerUsageHistory?.compactMap { $0 } ?? []
    }
}
