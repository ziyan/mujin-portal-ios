import Observation
import PortalKit
import SwiftUI

/// SiteModel is one site's picture: its alarms, robots, controllers and incidents.
@MainActor
@Observable
final class SiteModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let organizationId: String?
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var sites: [SiteSummary] = []
    /// The site shown. It is the place's state: kept across a push and a pop, remembered across launches, and changed only by the person (the picker) or when the site leaves the list.
    var selectedSiteId: String? {
        didSet {
            guard selectedSiteId != oldValue, pinnedSiteId == nil, remembersSelection else { return }
            selectionStore.save(selectedSiteId, accountKey: accountKey, organizationKey: organizationKey)
        }
    }
    /// A site a screen was opened for, which never changes to another.
    let pinnedSiteId: String?
    private let selectionStore = SiteSelectionStore()
    /// Screenshot runs do not remember a selection between launches.
    private let remembersSelection = DemoOptions.screen == nil
    private(set) var alarms: [SiteAlarm] = []
    private(set) var unavailableControllerCount = 0
    private(set) var robots = SiteRobots()
    private(set) var controllers: [ControllerSummary] = []
    private(set) var incidents: [IncidentSummary] = []
    private(set) var telemetry: SiteTelemetry?
    private(set) var cells: [SiteCell] = []
    private(set) var openTickets: [Ticket] = []
    private(set) var cameras: [Camera] = []
    /// Whether the stats are still being read, and whether they ever were: tiles are placeholders until the first time.
    private(set) var isLoadingStats = true
    private(set) var hasLoadedStats = false
    private(set) var orchestrators: [SiteOrchestrators] = []
    private(set) var members: [SiteMember] = []
    /// Whether the members page is the viewer's to see: a Mujin user, or an administrator of the site's organization.
    var viewerIsMujinUser = false
    var viewerPermissions: [String] = []
    var viewerOrganizationId: String?
    var canSeeMembers: Bool {
        SiteMembersAccess.canSee(isMujinUser: viewerIsMujinUser, permissions: viewerPermissions, viewerOrganizationId: viewerOrganizationId, siteOrganizationId: selectedSite?.organizationId)
    }
    private(set) var virtualControllers: [VirtualControllerSummary] = []
    var virtualControllerCount: Int { virtualControllers.count }

    let cache: ResponseCache?
    let accountKey: String

    init(connection: Connection, organizationId: String?, pinnedSiteId: String? = nil, cache: ResponseCache? = nil, accountKey: String = "", onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.organizationId = organizationId
        self.pinnedSiteId = pinnedSiteId
        self.cache = cache
        self.accountKey = accountKey
        self.onError = onError
        self.selectedSiteId = pinnedSiteId ?? (remembersSelection ? selectionStore.load(accountKey: accountKey, organizationKey: organizationId ?? "") : nil)
    }

    /// Names the model in the session's store and in a route: the organization, or empty for the person's own.
    var organizationKey: String { organizationId ?? "" }

    /// Names the model in the session's store: the organization, plus the site for a screen opened for one site.
    var sessionKey: String { organizationKey + (pinnedSiteId.map { "|" + $0 } ?? "") }

    /// Keeps the current site while it is listed, else restores the remembered one, else takes the first.
    private func resolveSelection() {
        if let pinnedSiteId { selectedSiteId = pinnedSiteId; return }
        selectedSiteId = SiteSelection.resolve(current: selectedSiteId, remembered: remembersSelection ? selectionStore.load(accountKey: accountKey, organizationKey: organizationKey) : nil, availableIds: sites.map(\.id))
    }

    var selectedSite: SiteSummary? { sites.first { $0.id == selectedSiteId } }

    /// Everything the page shows about one site, kept so coming back to it shows it at once.
    struct Snapshot: Sendable {
        var alarms: [SiteAlarm] = []
        var unavailableControllerCount = 0
        var robots = SiteRobots()
        var controllers: [ControllerSummary] = []
        var incidents: [IncidentSummary] = []
        var telemetry: SiteTelemetry?
        var cells: [SiteCell] = []
        var openTickets: [Ticket] = []
        var cameras: [Camera] = []
        var virtualControllers: [VirtualControllerSummary] = []
        var orchestrators: [SiteOrchestrators] = []
        var members: [SiteMember] = []
    }

    private func apply(_ snapshot: Snapshot) {
        alarms = snapshot.alarms
        unavailableControllerCount = snapshot.unavailableControllerCount
        robots = snapshot.robots
        controllers = snapshot.controllers
        incidents = snapshot.incidents
        telemetry = snapshot.telemetry
        cells = snapshot.cells
        openTickets = snapshot.openTickets
        cameras = snapshot.cameras
        virtualControllers = snapshot.virtualControllers
        orchestrators = snapshot.orchestrators
        members = snapshot.members
    }

    private func key(_ name: String, _ variables: String = "") -> CacheKey { CacheKey(accountKey: accountKey, name: name, variables: variables) }

    /// Shows what is held at once, and reads again only when it is old or `force` is set (pull to refresh).
    func loadSites(force: Bool = false) async {
        let sitesKey = key("sites", organizationKey)
        if let cache, let held = cache.hit(sitesKey, as: [SiteSummary].self) {
            sites = held.value
            resolveSelection()
            if selectedSiteId == nil { phase = .loaded } else { await loadDetails(force: force) }
            if held.isFresh && !force { return }
        }
        do {
            sites = try await connection.sites(organizationId: organizationId)
            cache?.store(sites, for: sitesKey)
            resolveSelection()
            if selectedSiteId == nil { phase = .loaded } else { await loadDetails(force: force) }
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    /// Reads everything about the selected site at once. A part the server
    /// cannot answer leaves that part empty rather than failing the screen.
    /// What was read before is shown first and replaced in place; the
    /// placeholders show only the first time.
    func loadDetails(force: Bool = false) async {
        guard let siteId = selectedSiteId else { return }
        let snapshotKey = key("site", "\(organizationKey)|\(siteId)")
        if let cache, let held = cache.hit(snapshotKey, as: Snapshot.self) {
            apply(held.value)
            phase = .loaded
            hasLoadedStats = true
            isLoadingStats = false
            if held.isFresh && !force { return }
        }
        isLoadingStats = !hasLoadedStats
        defer {
            isLoadingStats = false
            hasLoadedStats = true
        }
        let scopeId = organizationId ?? selectedSite?.organizationId
        let connection = connection
        var snapshot = Snapshot()
        async let alarmResult = try? connection.siteAlarms(siteId: siteId)
        async let robotResult = try? connection.siteRobots(siteId: siteId)
        async let controllerRows = try? connection.controllers(organizationId: scopeId)
        async let incidentRows = try? connection.incidents(organizationId: scopeId)
        let (alarmAnswer, robotAnswer, controllerAnswer, incidentAnswer) = await (alarmResult, robotResult, controllerRows, incidentRows)
        snapshot.alarms = alarmAnswer?.alarms ?? []
        snapshot.unavailableControllerCount = alarmAnswer?.unavailableControllerCount ?? 0
        snapshot.robots = robotAnswer ?? SiteRobots()
        snapshot.controllers = (controllerAnswer ?? []).filter { $0.siteId == siteId }
        snapshot.incidents = SiteData.incidents(incidentAnswer ?? [], siteId: siteId)
        if !hasLoadedStats {
            // The first time, what is read first shows as it arrives; the rest stays placeholders.
            alarms = snapshot.alarms
            unavailableControllerCount = snapshot.unavailableControllerCount
            robots = snapshot.robots
            controllers = snapshot.controllers
            incidents = snapshot.incidents
        }
        phase = .loaded
        // The overview's other parts arrive as they are read; each may be missing without failing the page.
        async let cellRows = try? connection.cells(siteId: siteId)
        async let ticketRows = try? connection.tickets(organizationId: scopeId, siteId: siteId)
        async let virtualRows = try? connection.virtualControllers(siteId: siteId, organizationId: scopeId)
        async let cameraRows = try? connection.cameras(siteId: siteId)
        snapshot.cameras = await cameraRows ?? []
        snapshot.cells = await cellRows ?? []
        snapshot.openTickets = (await ticketRows ?? []).filter { $0.siteId == siteId && $0.isOpenForWork }
        snapshot.virtualControllers = await virtualRows ?? []
        snapshot.orchestrators = (try? await connection.siteOrchestrators(siteId: siteId)) ?? []
        if canSeeMembers, let memberOrganizationId = selectedSite?.organizationId ?? scopeId {
            snapshot.members = (try? await connection.siteMembers(siteId: siteId, organizationId: memberOrganizationId, viewerOrganizationId: viewerOrganizationId)) ?? []
        }
        snapshot.telemetry = try? await connection.siteTelemetry(controllerIds: snapshot.controllers.map(\.id), virtualControllerIds: snapshot.virtualControllers.map(\.id))
        apply(snapshot)
        cache?.store(snapshot, for: snapshotKey)
    }
}

/// SiteView is the Site tab: a site's alarms, robots, controllers and
/// incidents, with the site picked from the title.
struct SiteView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// Limits the sites to one organization, for a Mujin user looking at a customer.
    let organizationId: String?
    /// A specific site, for a screen opened for that site. The switcher replaces it in place.
    let siteId: String?
    let embedsNavigation: Bool

    init(organizationId: String? = nil, siteId: String? = nil, embedsNavigation: Bool = true) {
        self.organizationId = organizationId
        self.siteId = siteId
        self.embedsNavigation = embedsNavigation
        _activeOrganizationId = State(initialValue: organizationId)
        _activeSiteId = State(initialValue: siteId)
    }

    @State private var activeOrganizationId: String?
    @State private var activeSiteId: String?
    @State private var model: SiteModel?
    @State private var path: [PortalRoute] = []

    var body: some View {
        if embedsNavigation {
            NavigationStack(path: $path) { screen.portalDestinations() }
        } else {
            screen
        }
    }

    /// The sites the switcher offers: every visible one for a Mujin user, the person's own organization's otherwise.
    private func switcherGroups(_ model: SiteModel) -> [SiteGroup] {
        if session.isStaff, !session.staffSites.sites.isEmpty {
            return SiteGroups.group(session.staffSites.sites, organizationNames: session.staffSites.organizationNames)
        }
        return SiteGroups.group(model.sites, organizationNames: session.organizationNames)
    }

    private var screen: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.selectedSite?.name ?? String(localized: "Site"))
        .navigationSubtitle(embedsNavigation ? "" : (session.organizationNames[activeOrganizationId ?? ""] ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        // The site picker and the bell belong to the Sites tab; a site pushed from a customer has its name and the assistant.
        .toolbar {
            if embedsNavigation {
                ToolbarItem(placement: .topBarLeading) { NotificationsBell() }
            }
            if let model, switcherGroups(model).reduce(0, { $0 + $1.sites.count }) > 1 {
                // The same switcher everywhere the site shows: tapping the name or the chevron lists the sites to switch to.
                ToolbarItem(placement: .principal) {
                    SiteSwitcher(
                        title: model.selectedSite?.name ?? String(localized: "Site"), groups: switcherGroups(model), selectedSiteId: model.selectedSiteId
                    ) { site in
                        if siteId == nil {
                            model.selectedSiteId = site.id
                        } else {
                            // A site opened for itself is replaced in place, without another screen on the stack.
                            activeOrganizationId = site.organizationId
                            activeSiteId = site.id
                        }
                    }
                }
            }
            if let site = model?.selectedSite {
                ToolbarItem(placement: .topBarTrailing) {
                    AskAboutButton(viewing: Viewing(kind: "site", id: site.id), subject: site.name ?? site.id)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .task(id: [activeOrganizationId ?? "", activeSiteId ?? ""]) {
            // The model is the session's, so it keeps what it loaded across a push and a pop or a switch of tabs.
            let siteModel = session.siteModel(for: activeOrganizationId, siteId: activeSiteId)
            if session.isStaff { try? await session.loadStaffSites() }
            model = siteModel
            await siteModel.loadSites()
            if appModel.isDemo {
                if DemoOptions.screen == "incident", let incident = siteModel.incidents.first { path.append(.incident(incident)) }
                if DemoOptions.screen == "controller" || DemoOptions.screen == "controller-screen" || DemoOptions.screen == "controller-menu", let controller = siteModel.controllers.first { path.append(.controller(controller)) }
                if DemoOptions.screen == "controller-apps" || DemoOptions.screen == "controller-app-open", let controller = siteModel.controllers.first(where: \.isOnline) { path.append(.controller(controller)) }
                if DemoOptions.screen == "controller-apps-offline", let controller = siteModel.controllers.first(where: { !$0.isOnline }) { path.append(.controller(controller)) }
                if DemoOptions.screen == "virtual-controller-apps", let virtual = siteModel.virtualControllers.first { path.append(.virtualController(virtual)) }
                if DemoOptions.screen == "controller-settings", let controller = siteModel.controllers.first {
                    path.append(.controller(controller))
                    path.append(.controllerSettings(controller))
                }
                if DemoOptions.screen == "controller-backups", let controller = siteModel.controllers.first {
                    path.append(.controller(controller))
                    path.append(.controllerBackups(controller))
                }
                if DemoOptions.screen == "virtual-controller-create" { path.append(.siteList(.virtualControllers, organizationKey: siteModel.sessionKey)) }
                if DemoOptions.screen == "virtual-controller" || DemoOptions.screen == "virtual-controller-menu" || DemoOptions.screen == "virtual-controller-snapshots", let virtual = siteModel.virtualControllers.first {
                    path.append(.virtualController(virtual))
                    if DemoOptions.screen == "virtual-controller-snapshots" { path.append(.virtualControllerSnapshots(virtual)) }
                }
                if DemoOptions.screen == "site-orchestrators" { path.append(.siteList(.orchestrators, organizationKey: siteModel.sessionKey)) }
                if DemoOptions.screen == "site-mobile-robots" { path.append(.siteList(.mobileRobots, organizationKey: siteModel.sessionKey)) }
                if DemoOptions.screen == "site-alarms" { path.append(.siteList(.alarms, organizationKey: siteModel.sessionKey)) }
                if DemoOptions.screen == "site-alarm-detail" || DemoOptions.screen == "site-alarm-metadata", let alarm = siteModel.alarms.first {
                    path.append(.alarm(alarm, controller: siteModel.controllers.first { $0.id == alarm.controllerId }))
                }
                if DemoOptions.screen == "site-members" { path.append(.siteList(.members, organizationKey: siteModel.sessionKey)) }
                if DemoOptions.screen == "site-back" {
                    // Choose the second site, push a list, and come back: the page must still show the second site.
                    siteModel.selectedSiteId = "site02"
                    await siteModel.loadDetails()
                    path.append(.siteList(.controllers, organizationKey: siteModel.sessionKey))
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    path.removeAll()
                }
                if DemoOptions.screen == "site-controllers" { path.append(.siteList(.controllers, organizationKey: siteModel.sessionKey)) }
                if DemoOptions.screen == "cameras" || DemoOptions.screen == "cameras-failed" { path.append(.siteList(.cameras, organizationKey: siteModel.sessionKey)) }
                if let camera = siteModel.cameras.first,
                    let target = DemoCameraScreens.target(for: DemoOptions.screen, camera: camera, incidentDetectedAt: siteModel.incidents.first?.detectedDate)
                {
                    path.append(.camera(target))
                }
            }
        }
        .task(id: model?.selectedSiteId) {
            if let model, model.phase == .loaded { await model.loadDetails() }
        }
    }

    @ViewBuilder
    private func content(_ model: SiteModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load sites", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.loadSites(force: true) } }
            }
        case .loaded:
            if model.sites.isEmpty {
                ContentUnavailableView {
                    Label("No sites yet", systemImage: "building.2")
                } description: {
                    Text("Sites you can see show up here.")
                }
            } else {
                List { PortalRows {
                    telemetrySection(model)
                    cellsSection(model)
                    tilesSection(model)
                    resourcesSection(model)
                    cameraSection(model)
                    alarmSection(model)
                    incidentSection(model)
                    ticketSection(model)
                } }
.portalRootList()
                .accessibilityIdentifier("sitePage")
                .routePushing()
                .refreshable { await model.loadDetails(force: true) }
            }
        }
    }

    // MARK: overview

    /// The last 24 hours, as the web page's telemetry cards show them.
    @ViewBuilder
    private func telemetrySection(_ model: SiteModel) -> some View {
        if let telemetry = model.telemetry, telemetry.machinesTotal > 0 {
            Section {
                tileGrid { telemetryTiles(telemetry) }
            } header: {
                Text("Last 24 hours")
            }
            // "View all" is a row of its own, below the tiles.
            if !model.cells.isEmpty {
                Section {
                    NavigationLink(value: PortalRoute.siteList(.telemetry, organizationKey: model.sessionKey)) { Text("View all").foregroundStyle(.tint) }
                }
            }
        } else if model.telemetry == nil, model.isLoadingStats {
            // The real layout, redacted, until the numbers arrive.
            Section {
                tileGrid { telemetryTiles(SiteTelemetry.placeholder) }
                    .placeholderWhileLoading(true)
            } header: {
                Text("Last 24 hours")
            }
        }
    }

    @ViewBuilder
    private func telemetryTiles(_ telemetry: SiteTelemetry) -> some View {
        StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
        StatTile(label: "Error rate", value: telemetry.errorRateText(), detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
        StatTile(label: "Robot throughput", value: telemetry.throughputText(), detail: "parts per hour", symbol: "speedometer")
        StatTile(label: "Machines", value: telemetry.machinesTotal.formatted(), detail: "\(telemetry.machinesReporting) reporting", symbol: "server.rack")
    }

    /// One card per cell with the machines it groups, the first few and the rest on a page of their own.
    @ViewBuilder
    private func cellsSection(_ model: SiteModel) -> some View {
        if !model.cells.isEmpty {
            Section("Cells") {
                ForEach(SiteSections.top(model.cells)) { cell in SiteRows.cell(cell) }
                showAll(.cells, model: model, count: model.cells.count, isShown: SiteSections.hasMore(model.cells))
            }
        } else if model.isLoadingStats, !model.hasLoadedStats {
            Section("Cells") {
                SiteRows.cell(SiteCell(id: "placeholder1", name: "Placeholder cell", controllerIds: ["a", "b"]))
                SiteRows.cell(SiteCell(id: "placeholder2", name: "Placeholder cell", controllerIds: ["a"]))
            }
            .placeholderWhileLoading(true)
        }
    }


    /// The counts, each a tile that opens its full list.
    private func tilesSection(_ model: SiteModel) -> some View {
        Section("Overview") {
            overviewTiles(model)
                .placeholderWhileLoading(model.isLoadingStats && !model.hasLoadedStats)
        }
    }

    @ViewBuilder
    private func overviewTiles(_ model: SiteModel) -> some View {
        Group {
            tileGrid {
                StatTile(label: "Controllers", value: model.controllers.count.formatted(), symbol: "server.rack",
                    route: .siteList(.controllers, organizationKey: model.sessionKey), identifier: "statTile.controllers")
                if model.virtualControllerCount > 0 {
                    StatTile(label: "Virtual controllers", value: model.virtualControllerCount.formatted(), symbol: "square.stack.3d.up",
                        route: .siteList(.virtualControllers, organizationKey: model.sessionKey), identifier: "statTile.virtualControllers")
                }
                StatTile(label: "Active alarms", value: model.alarms.count.formatted(), symbol: "bell.badge", tint: model.alarms.isEmpty ? nil : Color.statusError,
                    route: .siteList(.alarms, organizationKey: model.sessionKey), identifier: "statTile.alarms")
                StatTile(label: "Incidents", value: model.incidents.count.formatted(), symbol: "exclamationmark.triangle",
                    route: .siteList(.incidents, organizationKey: model.sessionKey), identifier: "statTile.incidents")
                StatTile(label: "Open tickets", value: model.openTickets.count.formatted(), symbol: "tray.full",
                    route: .siteList(.tickets, organizationKey: model.sessionKey), identifier: "statTile.tickets")
            }
        }
    }

    private func resourcesSection(_ model: SiteModel) -> some View {
        Section("Resources") {
            NavigationLink(value: PortalRoute.siteList(.controllers, organizationKey: model.sessionKey)) {
                LabeledContent("Controllers") { Text(model.controllers.count.formatted()).monospacedDigit() }
            }
            if model.robots.robotCount == 0 {
                LabeledContent("Mobile robots") { Text("None reported").foregroundStyle(.secondary) }
            } else {
                NavigationLink(value: PortalRoute.siteList(.mobileRobots, organizationKey: model.sessionKey)) {
                    LabeledContent("Mobile robots") { Text("\(model.robots.onlineCount) of \(model.robots.robotCount) online").monospacedDigit() }
                }
            }
            NavigationLink(value: PortalRoute.siteList(.orchestrators, organizationKey: model.sessionKey)) {
                LabeledContent("Orchestrators") {
                    let summary = SiteOrchestratorSummary(model.orchestrators)
                    HStack(spacing: 6) {
                        if summary.hasError { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusError).accessibilityLabel(Text("Has an error")) }
                        if summary.totalCount == 0 && summary.withoutOwnStatusCount == 0 {
                            Text("None reported").foregroundStyle(.secondary)
                        } else if summary.totalCount == 0 {
                            Text("\(summary.withoutOwnStatusCount) without a line status").foregroundStyle(.secondary)
                        } else {
                            Text("\(summary.runningCount) of \(summary.totalCount) running").monospacedDigit()
                        }
                    }
                }
            }
            if model.canSeeMembers {
                NavigationLink(value: PortalRoute.siteList(.members, organizationKey: model.sessionKey)) {
                    LabeledContent("Members") { Text(model.members.count.formatted()).monospacedDigit() }
                }
                if let siteOrganizationId = model.selectedSite?.organizationId, session.peopleAccess.hasPeopleScreens(in: siteOrganizationId) {
                    NavigationLink {
                        PeopleHubView(organizationId: siteOrganizationId)
                    } label: {
                        Text("Manage people")
                            .foregroundStyle(.primary)
                    }
                }
            }
            if model.robots.errorCount > 0 {
                LabeledContent("Robots with errors") { Text(model.robots.errorCount.formatted()).monospacedDigit().foregroundStyle(Color.statusError) }
            }
        }
    }

    private func tileGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        StatGrid { content() }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
    }

    /// The last row of a capped section: all of them on a page of their own.
    @ViewBuilder
    private func showAll(_ kind: SiteListKind, model: SiteModel, count: Int, isShown: Bool) -> some View {
        if isShown {
            NavigationLink(value: PortalRoute.siteList(kind, organizationKey: model.sessionKey)) { Text("Show all (\(count))").foregroundStyle(.tint) }
        }
    }

    // MARK: the few worst of each

    @ViewBuilder
    private func alarmSection(_ model: SiteModel) -> some View {
        if !model.alarms.isEmpty {
            Section("Alarms") {
                ForEach(SiteSections.top(model.alarms)) { alarm in SiteRows.alarmLink(alarm, controllers: model.controllers) }
                showAll(.alarms, model: model, count: model.alarms.count, isShown: SiteSections.hasMore(model.alarms))
            }
        }
    }


    /// The site's cameras: the first few with a picture, and all of them on a page of their own.
    @ViewBuilder
    private func cameraSection(_ model: SiteModel) -> some View {
        if !model.cameras.isEmpty {
            Section("Cameras") {
                ForEach(SiteSections.top(model.cameras)) { camera in
                    NavigationLink(value: PortalRoute.camera(CameraTarget(camera: camera))) { CameraRow(camera: camera) }
                }
                showAll(.cameras, model: model, count: model.cameras.count, isShown: SiteSections.hasMore(model.cameras))
            }
        }
    }

    @ViewBuilder
    private func incidentSection(_ model: SiteModel) -> some View {
        if !model.incidents.isEmpty {
            Section("Incidents") {
                ForEach(SiteSections.top(model.incidents)) { incident in
                    NavigationLink(value: PortalRoute.incident(incident)) { SiteRows.incident(incident) }
                }
                showAll(.incidents, model: model, count: model.incidents.count, isShown: SiteSections.hasMore(model.incidents))
            }
        }
    }


    @ViewBuilder
    private func ticketSection(_ model: SiteModel) -> some View {
        if !model.openTickets.isEmpty {
            Section("Tickets") {
                ForEach(SiteSections.top(model.openTickets)) { ticket in
                    NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                }
                showAll(.tickets, model: model, count: model.openTickets.count, isShown: SiteSections.hasMore(model.openTickets))
            }
        }
    }

    // MARK: the full lists

}

/// SiteListKind is a list the site page shows the first few rows of, opened whole.
enum SiteListKind: Hashable {
    case alarms
    case incidents
    case tickets
    case cells
    case controllers
    case virtualControllers
    case orchestrators
    case mobileRobots
    case members
    case telemetry
    case cameras

    var title: LocalizedStringKey {
        switch self {
        case .telemetry: "Last 24 hours"
        case .virtualControllers: "Virtual controllers"
        case .orchestrators: "Orchestrators"
        case .mobileRobots: "Mobile robots"
        case .members: "Members"
        case .alarms: "Alarms"
        case .incidents: "Incidents"
        case .tickets: "Tickets"
        case .cells: "Cells"
        case .controllers: "Controllers"
        case .cameras: "Cameras"
        }
    }
}

/// StatGrid lays tiles out two to a row on a phone, more on an iPad, and one
/// to a row at the large text sizes, so no label is cut.
struct StatGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 320 : 150), spacing: 10, alignment: .top)], spacing: 10) { content }
    }
}

/// StatTile is one number on the site page: a label, a large figure in
/// tabular digits, a line of detail and a symbol, on the cards' surface.
///
/// With a `route` the tile opens that screen. It is not a `NavigationLink`, which activates every other link of the
/// List row the tile grid is in (see RowControls.swift), so every grid of tiles that open screens gets it by passing
/// `route`, and its List applies `routePushing()`.
struct StatTile: View {
    @Environment(\.openRoute) private var openRoute
    let label: LocalizedStringKey
    let value: String
    var detail: LocalizedStringKey?
    let symbol: String
    var tint: Color?
    var route: PortalRoute?
    var identifier: String?

    var body: some View {
        if let route {
            card.rowTapTarget { openRoute(route) }.accessibilityIdentifier(identifier ?? "")
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(3)
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(12)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// ControllerDetailView is one controller: whether it is online, its
/// version, and the ways into it: its live and cloud web UIs in the built-in
/// browser, and its screen. An entry that cannot be opened says why.
struct ControllerDetailView: View {
    @Environment(AppModel.self) var appModel
    @Environment(SessionModel.self) var session
    @Environment(\.openURL) private var openURL
    let controller: ControllerSummary

    @State private var syncedUsers: SyncedUserCount?
    @State private var screenSession: WebSession?
    @State var editedComment: String?
    @State var alarms: [SiteAlarm] = []
    @State var orchestrators: SiteOrchestrators?
    @State var robots: [SiteRobots.Robot] = []
    @State var incidents: [IncidentSummary] = []
    @State var tickets: [Ticket] = []
    @State var telemetry: SiteTelemetry?
    @State var syncProgress: [ControllerSyncProgress] = []
    @State var isEditingComment = false
    @State var commentDraft = ""
    @State var isMoving = false
    @State var errorText: String?
    @State private var isLinkCopied = false

    var body: some View {
        ScrollViewReader { proxy in
            listContent
                .task { await scrollToAppsInDemo(proxy) }
        }
    }

    /// The demo's Apps screens start scrolled to the section, since the page is longer than the screen at large text sizes.
    private func scrollToAppsInDemo(_ proxy: ScrollViewProxy) async {
        guard appModel.isDemo, DemoOptions.screen?.contains("-apps") == true else { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        proxy.scrollTo(WebAppsSection.scrollID, anchor: .top)
    }

    private var listContent: some View {
        let server = session.account.server
        return List { PortalRows {
            Section {
                StatusValueRow(
                    title: "Status", symbol: controller.isOnline ? "checkmark.circle" : "circle.slash",
                    value: controller.isOnline ? LocalizedStringKey("Online") : LocalizedStringKey("Offline"))
                if let detail = editedComment ?? controller.detail {
                    LabeledContent("Comment") { Text(detail) }
                }
                // The release is what the controller runs; the hypervisor's version is a secondary row for staff.
                ReleaseRow(release: controller.release)
                if session.isStaff, let hypervisor = controller.hypervisorVersion {
                    LabeledContent("Hypervisor") { Text(hypervisor).foregroundStyle(.secondary) }
                }
                if let region = controller.region, !region.isEmpty {
                    LabeledContent("Region") { Text(region) }
                }
            }
            Section {
                entry(controller.liveEntry(server: server), title: "Open the live web UI", systemImage: "safari") { openURL($0) }
                entry(controller.cloudEntry(server: server, syncedUsers: syncedUsers), title: "Open the cloud web UI", systemImage: "cloud") { openURL($0) }
                entry(controller.screenEntry(server: server), title: "Screen", systemImage: "display") { url in
                    screenSession = appModel.makeScreenSession(for: session.account, url: url)
                }
            }
            if controller.can("controller:connect") {
                WebAppsSection(controllerId: controller.id, virtualControllerId: nil, canOpenCloud: controller.cloudEntry(server: server, syncedUsers: syncedUsers).isOpen)
            }
            extraSections
        } }
        .portalList()
        .task(id: controller.id) { await loadExtras() }
        .navigationTitle(controller.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskAboutButton(viewing: Viewing(kind: "controller", id: controller.id), subject: controller.displayName)
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                DetailMenu(demoScreen: "controller-menu") {
                    Section { LinkMenuItems(link: .controller(id: controller.id), isCopied: $isLinkCopied) }
                    if controller.canEdit || canMove {
                        Section {
                            if controller.canEdit {
                                Button {
                                    commentDraft = editedComment ?? controller.detail ?? ""
                                    isEditingComment = true
                                } label: { Label("Edit comment", systemImage: "pencil") }
                            }
                            if canMove {
                                Button { isMoving = true } label: { Label("Move to another site", systemImage: "arrow.right.square") }
                            }
                        }
                    }
                }
            }
        }
        .linkCopiedToast($isLinkCopied)
        .demoMenuHost(screen: "controller-menu")
        .alert("Edit comment", isPresented: $isEditingComment) {
            TextField("Comment", text: $commentDraft)
            Button("Save") { Task { await saveComment() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isMoving) { MoveControllerView(controller: controller) }
        .alert("Could not save", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .fullScreenCover(item: $screenSession) { screen in
            ControllerScreenView(session: screen, name: controller.displayName)
        }
        .task {
            syncedUsers = try? await appModel.connection(for: session.account).syncedUserCount(controllerId: controller.id)
            if appModel.isDemo, DemoOptions.screen == "controller-screen" {
                try? await Task.sleep(nanoseconds: 800_000_000)
                screenSession = appModel.makeScreenSession(for: session.account, url: ControllerLinks.screenURL(controllerId: controller.id, server: session.account.server)!)
            }
        }
    }

    /// A row that opens, or says why it cannot.
    @ViewBuilder
    private func entry(_ entry: ControllerEntry, title: LocalizedStringKey, systemImage: String, open: @escaping (URL) -> Void) -> some View {
        switch entry {
        case .open(let url):
            Button { open(url) } label: { Label(title, systemImage: systemImage).foregroundStyle(.tint) }
        case .blocked(let reason):
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage).foregroundStyle(.secondary)
                Text(Self.hint(for: reason)).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .hidden:
            EmptyView()
        }
    }

    private static func hint(for reason: ControllerBlock) -> LocalizedStringKey {
        switch reason {
        case .offline: "The controller is offline."
        case .noConnectPermission: "Opening the controller needs the controller:connect permission."
        case .noWritePermission: "Viewing the screen needs the controller:write permission."
        case .noSyncedUsers: "Cloud needs at least one user synced to Portal."
        case .syncedUsersUnavailable: "The synced users could not be counted."
        case .notRunning: "It is not running."
        }
    }
}

/// ControllerScreenView is the controller's screen, edge to edge: Portal's
/// screen page in a web view signed in by the handoff, with a close button
/// and the connection's state. The screen stays awake while it is open and
/// the page does not bounce, so a drag is a drag on the controller.
struct ControllerScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let session: WebSession
    let name: String

    var body: some View {
        // A thin bar of its own holds the close button, so the page is never drawn under it; the page fills the rest edge to edge.
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            WebViewHost(webView: session.webView)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AppDelegate.allowsLandscape = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            AppDelegate.allowsLandscape = false
            session.webView.stopLoading()
        }
    }
}

/// IncidentDetailView is one incident with its evidence, and the two
/// answers a reviewer gives: confirm or dismiss.
struct IncidentDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let incident: IncidentSummary

    @State private var evidence: [IncidentEvidence] = []
    @State private var cameraTargets: [IncidentCameraTarget] = []
    @State private var reviewStatus: String?
    @State private var errorText: String?

    var body: some View {
        let connection = appModel.connection(for: session.account)
        List { PortalRows {
            Section {
                if let description = incident.description, !description.isEmpty {
                    Text(description)
                }
                if let date = incident.detectedDate {
                    LabeledContent("Detected") { Text(date, format: .dateTime.month().day().hour().minute()) }
                }
                if let confidence = incident.confidence {
                    LabeledContent("Confidence") { Text(confidence, format: .percent.precision(.fractionLength(0))) }
                }
                LabeledContent("Review") { Text(reviewText) }
            }
            if !evidence.isEmpty {
                Section("Evidence") {
                    ForEach(evidence) { item in
                        ProducedFileRow(
                            file: ProducedFile(
                                attachmentId: item.attachmentId, name: item.filename ?? item.attachmentId, contentType: item.contentType ?? ""),
                            connection: connection)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if !cameraTargets.isEmpty {
                Section {
                    ForEach(cameraTargets, id: \.camera.id) { target in
                        NavigationLink(value: PortalRoute.camera(CameraTarget(camera: target.camera, startAtMS: recordingStartMS(target), markerMS: incident.detectedDate.map { $0.timeIntervalSince1970 * 1000 }))) {
                            Label(target.camera.displayName, systemImage: "play.rectangle")
                        }
                    }
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Plays the camera's recording from just before the incident was detected.")
                }
            }
            if (reviewStatus ?? incident.reviewStatus ?? "new") == "new" {
                Section {
                    Button {
                        Task { await review("confirmed") }
                    } label: {
                        Label("Confirm incident", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive) {
                        Task { await review("dismissed") }
                    } label: {
                        Label("Dismiss as not an incident", systemImage: "xmark.circle")
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Color.statusError)
                    }
                }
            }
        } }
.portalList()
        .navigationTitle(incident.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskAboutButton(viewing: Viewing(kind: "incident", id: incident.id), subject: incident.title ?? incident.id)
                    .labelStyle(.iconOnly)
            }
        }
        .task {
            evidence = (try? await connection.incidentEvidence(incidentId: incident.id)) ?? []
            cameraTargets = (try? await connection.incidentCameraTargets(incidentId: incident.id)) ?? []
        }
    }

    /// Ten seconds before the incident was detected, so the cause is in the picture; the stored clip's start when no time is known.
    private func recordingStartMS(_ target: IncidentCameraTarget) -> Double? {
        if let detected = incident.detectedDate { return detected.timeIntervalSince1970 * 1000 - 10_000 }
        return target.clipStartedAt.map { $0.timeIntervalSince1970 * 1000 }
    }

    private var reviewText: String {
        switch reviewStatus ?? incident.reviewStatus ?? "new" {
        case "confirmed": String(localized: "Confirmed")
        case "dismissed": String(localized: "Dismissed")
        case "resolved": String(localized: "Resolved")
        default: String(localized: "Needs review")
        }
    }

    private func review(_ status: String) async {
        errorText = nil
        do {
            try await appModel.connection(for: session.account).setIncidentReview(id: incident.id, reviewStatus: status)
            reviewStatus = status
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}

/// SiteTelemetryView is the last 24 hours of the whole site, as on the site
/// page, and then of each cell by itself.
struct SiteTelemetryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let model: SiteModel
    @State private var perCell: [(cell: SiteCell, telemetry: SiteTelemetry)] = []
    @State private var isLoading = true

    var body: some View {
        List { PortalRows {
            if let telemetry = model.telemetry {
                Section("Site") { tiles(telemetry) }
            } else if model.isLoadingStats {
                Section("Site") { tiles(SiteTelemetry.placeholder) }
                    .placeholderWhileLoading(true)
            }
            ForEach(perCell, id: \.cell.id) { entry in
                Section(entry.cell.name ?? entry.cell.id) { tiles(entry.telemetry) }
            }
            if isLoading {
                Section("Cells") { tiles(SiteTelemetry.placeholder) }
                    .placeholderWhileLoading(true)
            }
        } }
        .portalList()
        .navigationTitle("Last 24 hours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            let connection = appModel.connection(for: session.account)
            var rows: [(cell: SiteCell, telemetry: SiteTelemetry)] = []
            for cell in model.cells {
                if let telemetry = try? await connection.siteTelemetry(controllerIds: cell.controllerIds ?? [], virtualControllerIds: cell.virtualControllerIds ?? []) {
                    rows.append((cell, telemetry))
                }
            }
            perCell = rows
            isLoading = false
        }
    }

    private func tiles(_ telemetry: SiteTelemetry) -> some View {
        StatGrid {
            StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
            StatTile(label: "Error rate", value: telemetry.errorRateText(), detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
            StatTile(label: "Robot throughput", value: telemetry.throughputText(), detail: "parts per hour", symbol: "speedometer")
            StatTile(label: "Machines", value: telemetry.machinesTotal.formatted(), detail: "\(telemetry.machinesReporting) reporting", symbol: "server.rack")
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

/// VirtualControllerDetailView is a virtual controller: its name, whether it
/// runs, its web UI and, while it runs, its screen.
struct VirtualControllerDetailView: View {
    @Environment(AppModel.self) var appModel
    @Environment(SessionModel.self) var session
    @Environment(\.openURL) private var openURL
    let initial: VirtualControllerSummary
    @State private var current: VirtualControllerSummary?
    @State private var screenSession: WebSession?
    @Environment(\.dismiss) private var dismiss
    @State var liveTelemetry: SiteTelemetry?
    @State var liveAlarms: [SiteAlarm] = []
    @State var liveTickets: [Ticket] = []
    @State private var isLinkCopied = false

    init(virtual: VirtualControllerSummary) { initial = virtual }

    var virtual: VirtualControllerSummary { current ?? initial }

    var body: some View {
        ScrollViewReader { proxy in
            listContent
                .task { await scrollToAppsInDemo(proxy) }
        }
    }

    /// The demo's Apps screens start scrolled to the section, since the page is longer than the screen at large text sizes.
    private func scrollToAppsInDemo(_ proxy: ScrollViewProxy) async {
        guard appModel.isDemo, DemoOptions.screen?.contains("-apps") == true else { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        proxy.scrollTo(WebAppsSection.scrollID, anchor: .top)
    }

    private var listContent: some View {
        let server = session.account.server
        return List { PortalRows {
            Section {
                StatusValueRow(
                    title: "Status", symbol: virtual.isRunning ? "checkmark.circle" : "circle.slash",
                    value: virtual.isRunning ? LocalizedStringKey("Running") : LocalizedStringKey(virtual.status ?? ""))
                if let comment = virtual.comment, !comment.isEmpty { LabeledContent("Comment") { Text(comment) } }
                ReleaseRow(release: virtual.release)
                if let region = virtual.region, !region.isEmpty { LabeledContent("Region") { Text(region) } }
            }
            if virtual.canModify || virtual.canDestroy {
                Section {
                    NavigationLink(value: PortalRoute.virtualControllerSnapshots(virtual)) {
                        Label("Snapshots", systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                    }
                }
            }
            liveSections
            Section {
                row(virtual.webEntry(server: server), title: "Open the web UI", systemImage: "safari") { openURL($0) }
                row(virtual.screenEntry(server: server), title: "Screen", systemImage: "display") { url in
                    screenSession = appModel.makeScreenSession(for: session.account, url: url)
                }
            }
            if virtual.isRunning && virtual.can("virtual_controller:connect") {
                WebAppsSection(controllerId: nil, virtualControllerId: virtual.id, canOpenCloud: false)
            }
        } }
        .portalList()
        .task(id: virtual.id) { await loadLive() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskAboutButton(viewing: Viewing(kind: "virtual_controller", id: virtual.id), subject: virtual.displayName)
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                VirtualControllerMenu(virtual: virtual, isLinkCopied: $isLinkCopied, onChange: { current = $0 }, onDestroyed: { dismiss() })
            }
        }
        .linkCopiedToast($isLinkCopied)
        .demoMenuHost(screen: "virtual-controller-menu")
        .navigationTitle(virtual.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .fullScreenCover(item: $screenSession) { screen in
            ControllerScreenView(session: screen, name: virtual.displayName)
        }
    }

    @ViewBuilder
    private func row(_ entry: ControllerEntry, title: LocalizedStringKey, systemImage: String, open: @escaping (URL) -> Void) -> some View {
        switch entry {
        case .open(let url):
            Button { open(url) } label: { Label(title, systemImage: systemImage).foregroundStyle(.tint) }
        case .blocked(let reason):
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage).foregroundStyle(.secondary)
                Text(reason == .notRunning ? LocalizedStringKey("It is not running.") : LocalizedStringKey("Opening it needs the virtual_controller:connect permission."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .hidden:
            EmptyView()
        }
    }
}

/// SiteRows draws the rows the site page and its full lists share.
enum SiteRows {
    @ViewBuilder
    static func cell(_ cell: SiteCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.name ?? cell.id).foregroundStyle(.primary)
            Text("\(cell.machineCount) machines").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    static func alarm(_ alarm: SiteAlarm) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(alarm.message)
            } icon: {
                Image(systemName: alarm.severityRank <= 1 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(alarm.severityRank <= 1 ? Color.statusError : Color.statusWarning)
            }
            // The controller is named on every row. At the accessibility text sizes the parts go on separate lines.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(alarm.controllerId)
                    if let label = alarm.originLabel, !label.isEmpty, label != alarm.controllerId {
                        Text("\u{00B7}")
                        Text(label)
                    }
                    if let date = alarm.occurredDate {
                        Text("\u{00B7}")
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(alarm.controllerId).portalNameLine()
                    if let label = alarm.originLabel, !label.isEmpty, label != alarm.controllerId { Text(label).portalNameLine() }
                    if let date = alarm.occurredDate {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    /// An alarm row that opens the alarm in full when the controller reported an id to fetch it by.
    @ViewBuilder
    static func alarmLink(_ alarm: SiteAlarm, controllers: [ControllerSummary]) -> some View {
        if let logEntryId = alarm.logEntryId, !logEntryId.isEmpty {
            NavigationLink(value: PortalRoute.alarm(alarm, controller: controllers.first { $0.id == alarm.controllerId })) { Self.alarm(alarm) }
        } else {
            Self.alarm(alarm)
        }
    }

    @ViewBuilder
    static func incident(_ incident: IncidentSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(incident.title ?? incident.kind ?? "")
                .foregroundStyle(.primary)
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 2) {
                if incident.needsReview {
                    Label("Needs review", systemImage: "eye")
                        .foregroundStyle(Color.statusWarning)
                }
                if let date = incident.detectedDate {
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
    }
}

/// SiteListScreen is one of the site page's lists, whole.
struct SiteListScreen: View {
    let kind: SiteListKind
    let model: SiteModel

    var body: some View {
        List { PortalRows {
            switch kind {
            case .alarms:
                ForEach(model.alarms) { SiteRows.alarmLink($0, controllers: model.controllers) }
            case .incidents:
                ForEach(model.incidents) { incident in NavigationLink(value: PortalRoute.incident(incident)) { SiteRows.incident(incident) } }
            case .tickets:
                ForEach(model.openTickets) { ticket in NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) } }
            case .cells:
                ForEach(model.cells) { SiteRows.cell($0) }
            case .telemetry, .cameras:
                EmptyView()
            case .mobileRobots:
                ForEach(model.robots.robots) { RobotRow(robot: $0) }
            case .orchestrators:
                ForEach(model.orchestrators) { row in
                    Section(row.controllerId ?? "") {
                        if row.isAvailable == false {
                            Label("Not reachable", systemImage: "wifi.slash").foregroundStyle(.secondary)
                        } else if row.list.isEmpty {
                            Text("None reported").foregroundStyle(.secondary)
                        }
                        ForEach(row.list) { orchestrator in OrchestratorRow(orchestrator: orchestrator) }
                    }
                }
            case .members:
                ForEach(model.members) { member in
                    HStack(spacing: 12) {
                        UserAvatar(userId: member.id, name: member.shownName, hasAvatar: member.hasAvatar, modifiedAt: member.modifiedAt, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.shownName).portalNameLine()
                            if let email = member.email, !email.isEmpty, email != member.shownName { Text(email).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
            case .virtualControllers:
                ForEach(model.virtualControllers) { virtual in
                    NavigationLink(value: PortalRoute.virtualController(virtual)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(virtual.displayName).foregroundStyle(.primary)
                            Text(virtual.isRunning ? LocalizedStringKey("Running") : LocalizedStringKey(virtual.status ?? "")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            case .controllers:
                ForEach(model.controllers) { controller in
                    NavigationLink(value: PortalRoute.controller(controller)) {
                        HStack(spacing: 10) {
                            Image(systemName: controller.isOnline ? "checkmark.circle" : "circle.slash")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(controller.isOnline ? Text("Online") : Text("Offline"))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(controller.displayName).foregroundStyle(.primary)
                                if let detail = controller.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        } }
        .portalList()
        .accessibilityIdentifier("siteList.\(String(describing: kind))")
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            if kind == .virtualControllers {
                ToolbarItem(placement: .topBarTrailing) { VirtualControllerCreateButton(model: model) }
            }
        }
    }
}
