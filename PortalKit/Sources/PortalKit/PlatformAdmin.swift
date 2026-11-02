import Foundation

/// OrganizationRegistration is a request to start an organization, which a platform administrator decides.
public struct OrganizationRegistration: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let organizationName: String?
    public let country: String?
    /// `pending`, `approved` or `rejected`.
    public let status: String?
    public let createdAt: String?

    public var shownName: String { (organizationName ?? "").isEmpty ? (email ?? id) : organizationName! }
    public var isPending: Bool { status == "pending" }
    public var createdDate: Date? { PortalDate.parse(createdAt) }

    public var statusName: String {
        switch status {
        case "pending": return "Waiting"
        case "approved": return "Approved"
        case "rejected": return "Rejected"
        default: return status ?? ""
        }
    }
}

public enum RegistrationFilter: String, CaseIterable, Equatable, Sendable {
    case pending
    case approved
    case rejected
}

/// IncidentAlert says a person is told about the incidents of a site, from a detector confidence upwards.
public struct IncidentAlert: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let siteId: String?
    public let isEnabled: Bool?
    /// 0 to 1; nil means every incident.
    public let minimumConfidence: Double?
    public let createdAt: String?

    /// "70%" for a floor of 0.7, and "Every incident" when there is none.
    public var floorText: String {
        guard let minimumConfidence else { return "Every incident" }
        return "\(Int((minimumConfidence * 100).rounded()))%"
    }
}

public enum IncidentAlerts {
    /// The text of a confidence field as a floor: empty is no floor (nil), a percentage from 0 to 100 is a fraction. Invalid text is nil too,
    /// so callers check `isValid` first.
    public static func floor(fromPercentText text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let percent = Double(trimmed), (0...100).contains(percent) else { return nil }
        return percent / 100
    }

    /// Empty text is allowed (every incident); anything else has to be a percentage from 0 to 100.
    public static func isValid(percentText text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || floor(fromPercentText: trimmed) != nil
    }

    public static func percentText(_ floor: Double?) -> String {
        guard let floor else { return "" }
        let percent = (floor * 100).rounded()
        return String(Int(percent))
    }
}

extension Documents {
    public static let listOrganizationRegistrations = """
        query ListOrganizationRegistrations($status: String, $options: ListOptionsInput) {
          ListOrganizationRegistrations(status: $status, options: $options) {
            organizationRegistrations { id email organizationName country status createdAt }
            meta { totalCount }
          }
        }
        """

    public static let rejectOrganizationRegistration = """
        mutation RejectOrganizationRegistration($registrationId: String!, $reason: String) {
          RejectOrganizationRegistration(registrationId: $registrationId, reason: $reason) {
            organizationRegistration { id email organizationName country status createdAt }
          }
        }
        """

    public static let listIncidentAlerts = """
        query ListIncidentAlerts {
          ListIncidentSubscriptions { incidentSubscriptions { id siteId isEnabled minimumConfidence createdAt } }
        }
        """

    public static let subscribeToSiteIncidents = """
        mutation SubscribeToSiteIncidents($siteId: String!, $minimumConfidence: Float, $isEnabled: Boolean) {
          SubscribeToSiteIncidents(siteId: $siteId, minimumConfidence: $minimumConfidence, isEnabled: $isEnabled) {
            incidentSubscription { id siteId isEnabled minimumConfidence }
          }
        }
        """

    public static let unsubscribeFromSiteIncidents = """
        mutation UnsubscribeFromSiteIncidents($siteId: String!) { UnsubscribeFromSiteIncidents(siteId: $siteId) { siteId } }
        """

    static var platformAdminDocuments: [String] {
        [listOrganizationRegistrations, rejectOrganizationRegistration, listIncidentAlerts, subscribeToSiteIncidents, unsubscribeFromSiteIncidents]
    }
}

extension Connection {
    /// Requests to start an organization, newest first.
    public func organizationRegistrations(status: RegistrationFilter) async throws -> [OrganizationRegistration] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let organizationRegistrations: [OrganizationRegistration?]? }
            let ListOrganizationRegistrations: List?
        }
        let variables: [String: JSONValue] = ["status": .string(status.rawValue), "options": .object(["first": .number(200)])]
        let rows = try await execute(Documents.listOrganizationRegistrations, variables: variables, as: Answer.self)
            .ListOrganizationRegistrations?.organizationRegistrations?.compactMap { $0 } ?? []
        return rows.sorted { (PortalDate.parse($0.createdAt) ?? .distantPast) > (PortalDate.parse($1.createdAt) ?? .distantPast) }
    }

    public func rejectOrganizationRegistration(id: String, reason: String) async throws {
        var variables: [String: JSONValue] = ["registrationId": .string(id)]
        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { variables["reason"] = .string(reason) }
        _ = try await execute(Documents.rejectOrganizationRegistration, variables: variables, as: JSONValue.self)
    }

    public func incidentAlerts() async throws -> [IncidentAlert] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let incidentSubscriptions: [IncidentAlert?]? }
            let ListIncidentSubscriptions: List?
        }
        return try await execute(Documents.listIncidentAlerts, as: Answer.self).ListIncidentSubscriptions?.incidentSubscriptions?.compactMap { $0 } ?? []
    }

    public func setIncidentAlert(siteId: String, minimumConfidence: Double?, isEnabled: Bool) async throws {
        _ = try await execute(
            Documents.subscribeToSiteIncidents,
            variables: ["siteId": .string(siteId), "minimumConfidence": minimumConfidence.map { .number($0) } ?? .null, "isEnabled": .bool(isEnabled)], as: JSONValue.self)
    }

    public func removeIncidentAlert(siteId: String) async throws {
        _ = try await execute(Documents.unsubscribeFromSiteIncidents, variables: ["siteId": .string(siteId)], as: JSONValue.self)
    }
}
