import Foundation

extension Documents {
    public static let listAllVirtualControllers = """
        query ListAllVirtualControllers($organizationId: String, $options: ListOptionsInput) {
          ListVirtualControllers(organizationId: $organizationId, options: $options) { virtualControllers { \(virtualControllerFields) } meta { totalCount } }
        }
        """

    static var virtualControllerListDocuments: [String] { [listAllVirtualControllers] }
}

/// VirtualControllerFilter narrows the staff list of virtual controllers by text and by site.
public struct VirtualControllerFilter: Equatable, Sendable {
    public var query = ""
    public var siteId: String?

    public init(query: String = "", siteId: String? = nil) {
        self.query = query
        self.siteId = siteId
    }

    public func apply(_ rows: [VirtualControllerSummary], siteNames: [String: String]) -> [VirtualControllerSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            if row.status == "destroyed" { return false }
            if let siteId, row.siteId != siteId { return false }
            guard !text.isEmpty else { return true }
            return row.displayName.localizedCaseInsensitiveContains(text) || (row.comment ?? "").localizedCaseInsensitiveContains(text)
                || (siteNames[row.siteId ?? ""] ?? "").localizedCaseInsensitiveContains(text)
        }
    }
}

extension Connection {
    /// Every virtual controller the person can see, paged until the total the server reports, by name.
    public func allVirtualControllers(organizationId: String? = nil, pageSize: Int = 200) async throws -> [VirtualControllerSummary] {
        struct Answer: Decodable, Sendable {
            struct Meta: Decodable, Sendable { let totalCount: Int? }
            struct List: Decodable, Sendable {
                let virtualControllers: [VirtualControllerSummary]?
                let meta: Meta?
            }
            let ListVirtualControllers: List?
        }
        var rows: [VirtualControllerSummary] = []
        while true {
            var variables: [String: JSONValue] = ["options": .object(["first": .number(Double(pageSize)), "after": .number(Double(rows.count))])]
            if let organizationId { variables["organizationId"] = .string(organizationId) }
            let list = try await execute(Documents.listAllVirtualControllers, variables: variables, as: Answer.self).ListVirtualControllers
            let page = list?.virtualControllers ?? []
            rows += page
            if page.isEmpty { break }
            if let total = list?.meta?.totalCount, rows.count >= total { break }
            if page.count < pageSize, list?.meta?.totalCount == nil { break }
        }
        return rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
