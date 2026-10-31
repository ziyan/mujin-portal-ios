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
    var selectedSiteId: String?
    private(set) var alarms: [SiteAlarm] = []
    private(set) var unavailableControllerCount = 0
    private(set) var robots = SiteRobots()
    private(set) var controllers: [ControllerSummary] = []
    private(set) var incidents: [IncidentSummary] = []
    private(set) var telemetry: SiteTelemetry?
    private(set) var cells: [SiteCell] = []
    private(set) var openTickets: [Ticket] = []
    private(set) var virtualControllers: [VirtualControllerSummary] = []
    var virtualControllerCount: Int { virtualControllers.count }

    init(connection: Connection, organizationId: String?, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.organizationId = organizationId
        self.onError = onError
    }

    var selectedSite: SiteSummary? { sites.first { $0.id == selectedSiteId } }

    func loadSites() async {
        do {
            sites = try await connection.sites(organizationId: organizationId)
            if selectedSite == nil { selectedSiteId = sites.first?.id }
            if selectedSiteId == nil { phase = .loaded } else { await loadDetails() }
        } catch {
            onError(error)
            phase = .failed(error.userMessage)
        }
    }

    /// Reads everything about the selected site at once. A part the server
    /// cannot answer leaves that part empty rather than failing the screen.
    func loadDetails() async {
        guard let siteId = selectedSiteId else { return }
        let scopeId = organizationId ?? selectedSite?.organizationId
        let connection = connection
        async let alarmResult = try? connection.siteAlarms(siteId: siteId)
        async let robotResult = try? connection.siteRobots(siteId: siteId)
        async let controllerRows = try? connection.controllers(organizationId: scopeId)
        async let incidentRows = try? connection.incidents(organizationId: scopeId)
        let (alarmAnswer, robotAnswer, controllerAnswer, incidentAnswer) = await (alarmResult, robotResult, controllerRows, incidentRows)
        alarms = alarmAnswer?.alarms ?? []
        unavailableControllerCount = alarmAnswer?.unavailableControllerCount ?? 0
        robots = robotAnswer ?? SiteRobots()
        controllers = (controllerAnswer ?? []).filter { $0.siteId == siteId }
        incidents = SiteData.incidents(incidentAnswer ?? [], siteId: siteId)
        phase = .loaded
        // The overview's other parts arrive as they are read; each may be missing without failing the page.
        async let cellRows = try? connection.cells(siteId: siteId)
        async let ticketRows = try? connection.tickets(organizationId: scopeId, siteId: siteId)
        async let virtualRows = try? connection.virtualControllers(siteId: siteId, organizationId: scopeId)
        cells = await cellRows ?? []
        openTickets = (await ticketRows ?? []).filter { $0.siteId == siteId && $0.isOpenForWork }
        virtualControllers = await virtualRows ?? []
        telemetry = try? await connection.siteTelemetry(controllerIds: controllers.map(\.id), virtualControllerIds: virtualControllers.map(\.id))
    }
}

/// SiteView is the Site tab: a site's alarms, robots, controllers and
/// incidents, with the site picked from the title.
struct SiteView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// Limits the sites to one organization, for a Mujin user looking at a customer.
    var organizationId: String?
    var embedsNavigation = true

    @State private var model: SiteModel?
    @State private var path = NavigationPath()

    var body: some View {
        if embedsNavigation {
            NavigationStack(path: $path) { screen }
        } else {
            screen
        }
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
        .notificationsBell()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            if let model, model.sites.count > 1 {
                @Bindable var bindable = model
                Picker("Site", selection: $bindable.selectedSiteId) {
                    ForEach(model.sites) { site in
                        Text(site.name ?? site.id).tag(Optional(site.id))
                    }
                }
            }
        }
        .toolbar {
            if let site = model?.selectedSite {
                ToolbarItem(placement: .topBarTrailing) {
                    AskAboutButton(viewing: Viewing(kind: "site", id: site.id), subject: site.name ?? site.id)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .navigationDestination(for: SiteListKind.self) { kind in
            if let model {
                if kind == .telemetry {
                    SiteTelemetryView(model: model)
                } else {
                    fullList(kind, model)
                }
            }
        }
        .navigationDestination(for: String.self) { ticketId in
            TicketDetailView(ticketId: ticketId)
        }
        .navigationDestination(for: VirtualControllerSummary.self) { virtual in
            VirtualControllerDetailView(virtual: virtual)
        }
        .navigationDestination(for: IncidentSummary.self) { incident in
            IncidentDetailView(incident: incident)
        }
        .navigationDestination(for: ControllerSummary.self) { controller in
            ControllerDetailView(controller: controller)
        }
        .task(id: organizationId) {
            let siteModel = SiteModel(
                connection: appModel.connection(for: session.account), organizationId: organizationId,
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            model = siteModel
            await siteModel.loadSites()
            if appModel.isDemo {
                if DemoOptions.screen == "incident", let incident = siteModel.incidents.first { path.append(incident) }
                if DemoOptions.screen == "controller" || DemoOptions.screen == "controller-screen", let controller = siteModel.controllers.first { path.append(controller) }
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
                Button("Try again") { Task { await model.loadSites() } }
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
                    alarmSection(model)
                    incidentSection(model)
                    ticketSection(model)
                } }
.portalRootList()
                .refreshable { await model.loadDetails() }
            }
        }
    }

    // MARK: overview

    /// The last 24 hours, as the web page's telemetry cards show them.
    @ViewBuilder
    private func telemetrySection(_ model: SiteModel) -> some View {
        if let telemetry = model.telemetry, telemetry.machinesTotal > 0 {
            Section {
                tileGrid {
                    StatTile(label: "Picked parts", value: telemetry.pickedParts.formatted(), detail: "\(telemetry.pickOperations) pick operations", symbol: "shippingbox")
                    StatTile(label: "Error rate", value: telemetry.errorRateText, detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
                    StatTile(label: "Robot throughput", value: telemetry.throughputText, detail: "parts per hour", symbol: "speedometer")
                    StatTile(label: "Machines", value: telemetry.machinesTotal.formatted(), detail: "\(telemetry.machinesReporting) reporting", symbol: "server.rack")
                }
                if !model.cells.isEmpty {
                    NavigationLink(value: SiteListKind.telemetry) { Text("View all").foregroundStyle(.tint) }
                }
            } header: {
                Text("Last 24 hours")
            }
        }
    }

    /// One card per cell with the machines it groups, the first few and the rest on a page of their own.
    @ViewBuilder
    private func cellsSection(_ model: SiteModel) -> some View {
        if !model.cells.isEmpty {
            Section("Cells") {
                ForEach(SiteSections.top(model.cells)) { cell in cellRow(cell) }
                showAll(.cells, count: model.cells.count, isShown: SiteSections.hasMore(model.cells))
            }
        }
    }

    private func cellRow(_ cell: SiteCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.name ?? cell.id).foregroundStyle(.primary)
            Text("\(cell.machineCount) machines").font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// The counts, each a tile that opens its full list.
    private func tilesSection(_ model: SiteModel) -> some View {
        Section("Overview") {
            tileGrid {
                NavigationLink(value: SiteListKind.controllers) { StatTile(label: "Controllers", value: model.controllers.count.formatted(), symbol: "server.rack") }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
                if model.virtualControllerCount > 0 {
                    NavigationLink(value: SiteListKind.virtualControllers) { StatTile(label: "Virtual controllers", value: model.virtualControllerCount.formatted(), symbol: "square.stack.3d.up") }
                        .buttonStyle(.plain)
                }
                NavigationLink(value: SiteListKind.alarms) { StatTile(label: "Active alarms", value: model.alarms.count.formatted(), symbol: "bell.badge", tint: model.alarms.isEmpty ? nil : Color.statusError) }
                    .buttonStyle(.plain)
                NavigationLink(value: SiteListKind.incidents) { StatTile(label: "Incidents", value: model.incidents.count.formatted(), symbol: "exclamationmark.triangle") }
                    .buttonStyle(.plain)
                NavigationLink(value: SiteListKind.tickets) { StatTile(label: "Open tickets", value: model.openTickets.count.formatted(), symbol: "tray.full") }
                    .buttonStyle(.plain)
                    .navigationLinkIndicatorVisibility(.hidden)
            }
        }
    }

    private func resourcesSection(_ model: SiteModel) -> some View {
        Section("Resources") {
            NavigationLink(value: SiteListKind.controllers) {
                LabeledContent("Controllers") { Text(model.controllers.count.formatted()).monospacedDigit() }
            }
            LabeledContent("Mobile robots") {
                if model.robots.robotCount == 0 {
                    Text("None reported").foregroundStyle(.secondary)
                } else {
                    Text("\(model.robots.onlineCount) of \(model.robots.robotCount) online").monospacedDigit()
                }
            }
            if model.robots.errorCount > 0 {
                LabeledContent("Robots with errors") { Text(model.robots.errorCount.formatted()).monospacedDigit().foregroundStyle(Color.statusError) }
            }
        }
    }

    private func tileGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        StatGrid { content() }
            .navigationLinkIndicatorVisibility(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
    }

    /// The last row of a capped section: all of them on a page of their own.
    @ViewBuilder
    private func showAll(_ kind: SiteListKind, count: Int, isShown: Bool) -> some View {
        if isShown {
            NavigationLink(value: kind) { Text("Show all (\(count))").foregroundStyle(.tint) }
        }
    }

    // MARK: the few worst of each

    @ViewBuilder
    private func alarmSection(_ model: SiteModel) -> some View {
        if !model.alarms.isEmpty {
            Section("Alarms") {
                ForEach(SiteSections.top(model.alarms)) { alarm in alarmRow(alarm) }
                showAll(.alarms, count: model.alarms.count, isShown: SiteSections.hasMore(model.alarms))
            }
        }
    }

    private func alarmRow(_ alarm: SiteAlarm) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(alarm.message)
            } icon: {
                Image(systemName: alarm.severityRank <= 1 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(alarm.severityRank <= 1 ? Color.statusError : Color.statusWarning)
            }
            // At the accessibility text sizes the two parts go on separate lines.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(alarm.originLabel ?? alarm.controllerId)
                    if let date = alarm.occurredDate {
                        Text("\u{00B7}")
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(alarm.originLabel ?? alarm.controllerId)
                    if let date = alarm.occurredDate {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func incidentSection(_ model: SiteModel) -> some View {
        if !model.incidents.isEmpty {
            Section("Incidents") {
                ForEach(SiteSections.top(model.incidents)) { incident in
                    NavigationLink(value: incident) { incidentRow(incident) }
                }
                showAll(.incidents, count: model.incidents.count, isShown: SiteSections.hasMore(model.incidents))
            }
        }
    }

    private func incidentRow(_ incident: IncidentSummary) -> some View {
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

    @ViewBuilder
    private func ticketSection(_ model: SiteModel) -> some View {
        if !model.openTickets.isEmpty {
            Section("Tickets") {
                ForEach(SiteSections.top(model.openTickets)) { ticket in
                    NavigationLink(value: ticket.id) { TicketRow(ticket: ticket) }
                }
                showAll(.tickets, count: model.openTickets.count, isShown: SiteSections.hasMore(model.openTickets))
            }
        }
    }

    // MARK: the full lists

    @ViewBuilder
    private func fullList(_ kind: SiteListKind, _ model: SiteModel) -> some View {
        List { PortalRows {
            switch kind {
            case .alarms:
                ForEach(model.alarms) { alarmRow($0) }
            case .incidents:
                ForEach(model.incidents) { incident in NavigationLink(value: incident) { incidentRow(incident) } }
            case .tickets:
                ForEach(model.openTickets) { ticket in NavigationLink(value: ticket.id) { TicketRow(ticket: ticket) } }
            case .cells:
                ForEach(model.cells) { cellRow($0) }
            case .telemetry:
                EmptyView()
            case .virtualControllers:
                ForEach(model.virtualControllers) { virtual in
                    NavigationLink(value: virtual) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(virtual.displayName).foregroundStyle(.primary)
                            Text(virtual.isRunning ? LocalizedStringKey("Running") : LocalizedStringKey(virtual.status ?? "")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            case .controllers:
                ForEach(model.controllers) { controller in
                    NavigationLink(value: controller) {
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
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

/// SiteListKind is a list the site page shows the first few rows of, opened whole.
enum SiteListKind: Hashable {
    case alarms
    case incidents
    case tickets
    case cells
    case controllers
    case virtualControllers
    case telemetry

    var title: LocalizedStringKey {
        switch self {
        case .telemetry: "Last 24 hours"
        case .virtualControllers: "Virtual controllers"
        case .alarms: "Alarms"
        case .incidents: "Incidents"
        case .tickets: "Tickets"
        case .cells: "Cells"
        case .controllers: "Controllers"
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
struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    var detail: LocalizedStringKey?
    let symbol: String
    var tint: Color?

    var body: some View {
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
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.openURL) private var openURL
    let controller: ControllerSummary

    @State private var syncedUsers: SyncedUserCount?
    @State private var screenSession: WebSession?

    var body: some View {
        let server = session.account.server
        List { PortalRows {
            Section {
                HStack {
                    Text("Status")
                    Spacer(minLength: 8)
                    Label(controller.isOnline ? "Online" : "Offline", systemImage: controller.isOnline ? "checkmark.circle" : "circle.slash")
                        .foregroundStyle(.secondary)
                }
                if let detail = controller.detail {
                    LabeledContent("Comment") { Text(detail) }
                }
                if let version = controller.version {
                    LabeledContent("Version") { Text(version) }
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
        } }
        .portalList()
        .navigationTitle(controller.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskAboutButton(viewing: Viewing(kind: "controller", id: controller.id), subject: controller.displayName)
                    .labelStyle(.iconOnly)
            }
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
        WebViewHost(webView: session.webView)
            .ignoresSafeArea()
            .background(Color.black)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Close")
                    HStack(spacing: 6) {
                        if session.isLoading { ProgressView().controlSize(.small) } else { Image(systemName: "dot.radiowaves.left.and.right").accessibilityHidden(true) }
                        Text(session.isLoading ? LocalizedStringKey("Connecting\u{2026}") : LocalizedStringKey("Connected"))
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityElement(children: .combine)
                }
                .padding(.leading, 12)
                .padding(.top, 8)
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .toolbarVisibility(.hidden, for: .tabBar)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                AppDelegate.allowsLandscape = true
                session.webView.scrollView.bounces = false
                session.webView.scrollView.alwaysBounceVertical = false
                session.webView.scrollView.alwaysBounceHorizontal = false
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
        }
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
            }
            ForEach(perCell, id: \.cell.id) { entry in
                Section(entry.cell.name ?? entry.cell.id) { tiles(entry.telemetry) }
            }
            if isLoading { Section { ProgressView() } }
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
            StatTile(label: "Error rate", value: telemetry.errorRateText, detail: "\(telemetry.interventions) of \(telemetry.pickedParts) picks needed a person", symbol: "exclamationmark.arrow.triangle.2.circlepath")
            StatTile(label: "Robot throughput", value: telemetry.throughputText, detail: "parts per hour", symbol: "speedometer")
            StatTile(label: "Machines", value: telemetry.machinesTotal.formatted(), detail: "\(telemetry.machinesReporting) reporting", symbol: "server.rack")
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

/// VirtualControllerDetailView is a virtual controller: its name, whether it
/// runs, its web UI and, while it runs, its screen.
struct VirtualControllerDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.openURL) private var openURL
    let virtual: VirtualControllerSummary
    @State private var screenSession: WebSession?

    var body: some View {
        let server = session.account.server
        List { PortalRows {
            Section {
                LabeledContent("Status") {
                    Label(virtual.isRunning ? "Running" : LocalizedStringKey(virtual.status ?? ""), systemImage: virtual.isRunning ? "checkmark.circle" : "circle.slash")
                        .foregroundStyle(.secondary)
                }
                if let comment = virtual.comment, !comment.isEmpty { LabeledContent("Comment") { Text(comment) } }
                if let region = virtual.region, !region.isEmpty { LabeledContent("Region") { Text(region) } }
            }
            Section {
                row(virtual.webEntry(server: server), title: "Open the web UI", systemImage: "safari") { openURL($0) }
                row(virtual.screenEntry(server: server), title: "Screen", systemImage: "display") { url in
                    screenSession = appModel.makeScreenSession(for: session.account, url: url)
                }
            }
        } }
        .portalList()
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
