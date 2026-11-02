import Foundation

/// AlarmDetail is everything the controller reports about one active alarm: the fields the list leaves out
/// (what raised it, and its metadata) are fetched when the alarm is opened.
public struct AlarmDetail: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public let key: String
        public let value: String
        public var id: String { key }
    }

    public let logEntryId: String
    public let alarmLevel: String?
    public let alarmStatus: String?
    public let alarmMessage: String?
    public let occurredAt: String?
    public let originKind: String?
    public let originControllerId: String?
    public let originEntries: [Entry]
    public let metadataEntries: [Entry]

    /// The metadata as pretty-printed JSON with sorted keys. A value that is itself JSON (an object, an
    /// array, a number or a flag sent as text) is shown as that JSON, not as a quoted string.
    public var metadataJSON: String {
        var object: [String: JSONValue] = [:]
        for entry in metadataEntries {
            if let data = entry.value.data(using: .utf8), let parsed = try? JSONDecoder().decode(JSONValue.self, from: data), parsed != .null {
                object[entry.key] = parsed
            } else {
                object[entry.key] = .string(entry.value)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(object)), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// ControllerTime renders a timestamp the way the web does for a controller: at the clock of the offset the
/// timestamp itself carries, never the viewer's zone, and says which offset that was.
public enum ControllerTime {
    /// The offset an ISO 8601 timestamp ends with (`-04:00`, `+0900`, or `Z`), in seconds.
    public static func offsetSeconds(of text: String) -> Int? {
        if text.hasSuffix("Z") { return 0 }
        guard let match = text.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) else { return nil }
        let digits = text[match].filter(\.isNumber)
        guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
        let seconds = hours * 3600 + minutes * 60
        return text[match].hasPrefix("-") ? -seconds : seconds
    }

    /// "Nov 2, 2026 at 9:15 AM UTC-04:00", or the same at the viewer's zone, labeled as such, when the
    /// timestamp carries no offset. Nil when the text is not a timestamp.
    public static func text(_ iso: String?, locale: Locale = .current) -> String? {
        guard let iso, let date = PortalDate.parse(iso) else { return nil }
        let offset = offsetSeconds(of: iso)
        let zone = offset.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
        let style = Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: zone)
        let rendered = date.formatted(style)
        return "\(rendered) \(label(offsetSeconds: offset ?? zone.secondsFromGMT(for: date)))"
    }

    /// "UTC", "UTC-04:00", "UTC+09:30".
    public static func label(offsetSeconds: Int) -> String {
        if offsetSeconds == 0 { return "UTC" }
        let magnitude = abs(offsetSeconds)
        let hours = magnitude / 3600
        let minutes = magnitude % 3600 / 60
        return "UTC\(offsetSeconds < 0 ? "-" : "+")\(hours < 10 ? "0" : "")\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }
}

extension Documents {
    public static let getAlarmDetail = """
        query GetAlarmDetail($controllerId: String, $logEntryId: String!) {
          GetAlarmDetail(controllerId: $controllerId, logEntryId: $logEntryId) {
            logEntryId alarmStatus alarmLevel alarmMessage occurredAt originKind originControllerId
            originFields { key value }
            metadata { key value }
          }
        }
        """
}

extension Connection {
    public func alarmDetail(controllerId: String, logEntryId: String) async throws -> AlarmDetail? {
        struct Pair: Decodable, Sendable {
            let key: String?
            let value: String?
        }
        struct Detail: Decodable, Sendable {
            let logEntryId: String?
            let alarmStatus: String?
            let alarmLevel: String?
            let alarmMessage: String?
            let occurredAt: String?
            let originKind: String?
            let originControllerId: String?
            let originFields: [Pair]?
            let metadata: [Pair]?
        }
        struct Answer: Decodable, Sendable { let GetAlarmDetail: Detail? }
        let variables: [String: JSONValue] = ["controllerId": .string(controllerId), "logEntryId": .string(logEntryId)]
        guard let detail = try await execute(Documents.getAlarmDetail, variables: variables, as: Answer.self).GetAlarmDetail else { return nil }
        func entries(_ pairs: [Pair]?) -> [AlarmDetail.Entry] {
            (pairs ?? []).compactMap { pair in pair.key.map { AlarmDetail.Entry(key: $0, value: pair.value ?? "") } }
        }
        return AlarmDetail(
            logEntryId: detail.logEntryId ?? logEntryId, alarmLevel: detail.alarmLevel, alarmStatus: detail.alarmStatus, alarmMessage: detail.alarmMessage,
            occurredAt: detail.occurredAt, originKind: detail.originKind, originControllerId: detail.originControllerId,
            originEntries: entries(detail.originFields), metadataEntries: entries(detail.metadata))
    }
}
