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

    /// "1.4%": a tenth of a percent, in the locale's own marks.
    public func errorRateText(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: errorRate)) ?? "0%"
    }

    /// Parts an hour, grouped as the locale groups: a whole number from 100 up ("1,396"), one decimal below it ("58.3").
    public func throughputText(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = robotThroughputPartsPerHour >= 100 ? 0 : 1
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: robotThroughputPartsPerHour)) ?? "0"
    }

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
        query ListSiteVirtualControllers($organizationId: String, $cellId: String, $options: ListOptionsInput) {
          ListVirtualControllers(organizationId: $organizationId, cellId: $cellId, options: $options) {
            virtualControllers { id name comment siteId region status statusMessage viewerCapabilities releaseId releaseImageId pausedAt size product }
          }
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
        let rows = try await telemetrySummaries(controllerIds: ids, virtualControllerIds: virtualIds)
        return SiteTelemetry(summaries: rows, machinesTotal: ids.count + virtualIds.count)
    }

    /// The summaries of explicit machines, as the server answers them.
    func telemetrySummaries(controllerIds: [String], virtualControllerIds: [String]) async throws -> [TelemetrySummary] {
        struct Answer: Decodable, Sendable { let ListControllerTelemetrySummaries: [TelemetrySummary]? }
        return try await execute(
            Documents.listControllerTelemetrySummaries,
            variables: ["controllerIds": .array(controllerIds.map { .string($0) }), "virtualControllerIds": .array(virtualControllerIds.map { .string($0) })], as: Answer.self
        ).ListControllerTelemetrySummaries ?? []
    }

    public func cells(siteId: String) async throws -> [SiteCell] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let cells: [SiteCell]? }
            let ListCells: List?
        }
        let rows = try await execute(Documents.listCells, variables: ["siteId": .string(siteId), "options": .object(["first": .number(100)])], as: Answer.self).ListCells?.cells ?? []
        return rows.filter { $0.isArchived != true }
    }

    /// The site's virtual controllers.
    public func virtualControllers(siteId: String, organizationId: String?, cellId: String? = nil) async throws -> [VirtualControllerSummary] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let virtualControllers: [VirtualControllerSummary]? }
            let ListVirtualControllers: List?
        }
        var variables: [String: JSONValue] = ["options": .object(["first": .number(200)])]
        if let organizationId { variables["organizationId"] = .string(organizationId) }
        if let cellId { variables["cellId"] = .string(cellId) }
        let rows = try await execute(Documents.listSiteVirtualControllers, variables: variables, as: Answer.self).ListVirtualControllers?.virtualControllers ?? []
        return rows.filter { $0.siteId == siteId && $0.status != "destroyed" }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

/// VirtualControllerSummary is a controller that runs in Portal's cloud. It keeps its name, unlike a physical controller, which is named by its id.
public struct VirtualControllerSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let comment: String?
    public let siteId: String?
    public let region: String?
    /// `pending`, `provisioning`, `running`, `paused`, `error`, `destroying` or `destroyed`.
    public let status: String?
    public let statusMessage: String?
    public let viewerCapabilities: [String]?
    public let releaseId: String?
    public let releaseImageId: String?
    /// Set while the virtual controller is meant to be paused, even before its status says so.
    public let pausedAt: String?
    public let size: String?
    public let product: String?

    public init(id: String, name: String? = nil, comment: String? = nil, siteId: String? = nil, region: String? = nil, status: String? = "running", statusMessage: String? = nil, viewerCapabilities: [String]? = nil, releaseId: String? = nil, releaseImageId: String? = nil, pausedAt: String? = nil, size: String? = nil, product: String? = nil) {
        self.pausedAt = pausedAt
        self.size = size
        self.product = product
        self.releaseId = releaseId
        self.releaseImageId = releaseImageId
        self.id = id
        self.name = name
        self.comment = comment
        self.siteId = siteId
        self.region = region
        self.status = status
        self.statusMessage = statusMessage
        self.viewerCapabilities = viewerCapabilities
    }

    public var displayName: String { (name ?? "").isEmpty ? id : name! }
    public var isRunning: Bool { status == "running" }
    public var release: ControllerRelease { ControllerRelease(releaseId: releaseId, releaseImageId: releaseImageId) }
    public func can(_ capability: String) -> Bool { viewerCapabilities?.contains(capability) ?? false }

    /// Its web UI, through Portal's virtual controller proxy.
    public func webEntry(server: ServerAddress) -> ControllerEntry {
        guard isRunning else { return .blocked(.notRunning) }
        guard can("virtual_controller:connect") else { return .blocked(.noConnectPermission) }
        return ControllerLinks.virtualURL(virtualControllerId: id, server: server).map(ControllerEntry.open) ?? .hidden
    }

    /// Its screen, while it runs.
    public func screenEntry(server: ServerAddress) -> ControllerEntry {
        guard isRunning else { return .blocked(.notRunning) }
        return ControllerLinks.virtualScreenURL(virtualControllerId: id, server: server).map(ControllerEntry.open) ?? .hidden
    }
}
