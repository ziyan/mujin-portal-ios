import Foundation

/// TelemetrySummary is one machine's last 24 hours: the numbers the site page adds up.
public struct TelemetrySummary: Codable, Equatable, Sendable {
    public struct Totals: Codable, Equatable, Sendable {
        public let pickOperationCount: Int?
        public let pickedPartCount: Int?
        public let humanInterventionCount: Int?
        public let directRobotThroughputPartsPerHour: Double?

        public init(pickOperationCount: Int? = nil, pickedPartCount: Int? = nil, humanInterventionCount: Int? = nil, directRobotThroughputPartsPerHour: Double? = nil) {
            self.pickOperationCount = pickOperationCount
            self.pickedPartCount = pickedPartCount
            self.humanInterventionCount = humanInterventionCount
            self.directRobotThroughputPartsPerHour = directRobotThroughputPartsPerHour
        }
    }

    public let controllerId: String?
    public let virtualControllerId: String?
    public let isAvailable: Bool?
    public let activeAlarmCount: Int?
    public let totals: Totals?

    public init(controllerId: String? = nil, virtualControllerId: String? = nil, isAvailable: Bool? = true, activeAlarmCount: Int? = nil, totals: Totals? = nil) {
        self.controllerId = controllerId
        self.virtualControllerId = virtualControllerId
        self.isAvailable = isAvailable
        self.activeAlarmCount = activeAlarmCount
        self.totals = totals
    }
}

/// SiteTelemetry is what the site page shows for the trailing 24 hours,
/// summed over the site's machines as the web page sums it: picked parts
/// with their pick operations, the error rate (interventions of picks) and
/// the robots' throughput in parts an hour.
public struct SiteTelemetry: Equatable, Sendable {
    public var pickedParts = 0
    public var pickOperations = 0
    public var interventions = 0
    public var robotThroughputPartsPerHour = 0.0
    public var machinesTotal = 0
    public var machinesReporting = 0

    public init() {}

    public init(summaries: [TelemetrySummary], machinesTotal: Int) {
        for summary in summaries where summary.isAvailable == true {
            pickedParts += summary.totals?.pickedPartCount ?? 0
            pickOperations += summary.totals?.pickOperationCount ?? 0
            interventions += summary.totals?.humanInterventionCount ?? 0
            robotThroughputPartsPerHour += summary.totals?.directRobotThroughputPartsPerHour ?? 0
            machinesReporting += 1
        }
        self.machinesTotal = machinesTotal
    }

    public var errorRate: Double { pickedParts > 0 ? Double(interventions) / Double(pickedParts) : 0 }

    /// "1.4%": a tenth of a percent, as the web page rounds it.
    public var errorRateText: String { "\(Self.trimmed((errorRate * 1000).rounded() / 10))%" }
    public var throughputText: String { Self.trimmed((robotThroughputPartsPerHour * 10).rounded() / 10) }

    static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// SiteCell is a cell of a site: a group of its machines.
public struct SiteCell: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let description: String?
    public let controllerIds: [String]?
    public let virtualControllerIds: [String]?
    public let cameraIds: [String]?
    public let isArchived: Bool?

    public init(id: String, name: String? = nil, description: String? = nil, controllerIds: [String]? = nil, virtualControllerIds: [String]? = nil, cameraIds: [String]? = nil, isArchived: Bool? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.controllerIds = controllerIds
        self.virtualControllerIds = virtualControllerIds
        self.cameraIds = cameraIds
        self.isArchived = isArchived
    }

    public var machineCount: Int { (controllerIds?.count ?? 0) + (virtualControllerIds?.count ?? 0) }
}

/// SiteSections caps a section of the site page: the first few rows, and how many more there are.
public enum SiteSections {
    public static let shownCount = 3

    public static func top<Element>(_ rows: [Element]) -> [Element] { Array(rows.prefix(shownCount)) }
    public static func hasMore<Element>(_ rows: [Element]) -> Bool { rows.count > shownCount }
}

extension Documents {
    public static let listControllerTelemetrySummaries = """
        query ListControllerTelemetrySummaries($controllerIds: [String], $virtualControllerIds: [String]) {
          ListControllerTelemetrySummaries(controllerIds: $controllerIds, virtualControllerIds: $virtualControllerIds) {
            controllerId virtualControllerId isAvailable activeAlarmCount
            totals { pickOperationCount pickedPartCount humanInterventionCount directRobotThroughputPartsPerHour }
          }
        }
        """

    public static let listCells = """
        query ListCells($siteId: String, $options: ListOptionsInput) {
          ListCells(siteId: $siteId, options: $options) { cells { id name description controllerIds virtualControllerIds cameraIds isArchived } }
        }
        """

    public static let listSiteVirtualControllers = """
        query ListSiteVirtualControllers($organizationId: String, $options: ListOptionsInput) {
          ListVirtualControllers(organizationId: $organizationId, options: $options) { virtualControllers { id siteId } }
        }
        """

    static var siteOverviewDocuments: [String] { [listControllerTelemetrySummaries, listCells, listSiteVirtualControllers] }
}

extension Connection {
    /// The last 24 hours of up to 50 machines, summed. A machine that did not answer is counted apart.
    public func siteTelemetry(controllerIds: [String], virtualControllerIds: [String] = []) async throws -> SiteTelemetry {
        let ids = Array(controllerIds.prefix(50))
        let virtualIds = Array(virtualControllerIds.prefix(max(0, 50 - ids.count)))
        guard !ids.isEmpty || !virtualIds.isEmpty else { return SiteTelemetry() }
        struct Answer: Decodable, Sendable { let ListControllerTelemetrySummaries: [TelemetrySummary]? }
        let rows = try await execute(
            Documents.listControllerTelemetrySummaries,
            variables: ["controllerIds": .array(ids.map { .string($0) }), "virtualControllerIds": .array(virtualIds.map { .string($0) })], as: Answer.self
        ).ListControllerTelemetrySummaries ?? []
        return SiteTelemetry(summaries: rows, machinesTotal: ids.count + virtualIds.count)
    }

    public func cells(siteId: String) async throws -> [SiteCell] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let cells: [SiteCell]? }
            let ListCells: List?
        }
        let rows = try await execute(Documents.listCells, variables: ["siteId": .string(siteId), "options": .object(["first": .number(100)])], as: Answer.self).ListCells?.cells ?? []
        return rows.filter { $0.isArchived != true }
    }

    /// The ids of the site's virtual controllers.
    public func virtualControllerIds(siteId: String, organizationId: String?) async throws -> [String] {
        struct Row: Decodable, Sendable {
            let id: String
            let siteId: String?
        }
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let virtualControllers: [Row]? }
            let ListVirtualControllers: List?
        }
        var variables: [String: JSONValue] = ["options": .object(["first": .number(200)])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        let rows = try await execute(Documents.listSiteVirtualControllers, variables: variables, as: Answer.self).ListVirtualControllers?.virtualControllers ?? []
        return rows.filter { $0.siteId == siteId }.map(\.id)
    }
}
