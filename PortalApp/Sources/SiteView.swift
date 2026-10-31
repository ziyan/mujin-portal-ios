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
                    alarmSection(model)
                    robotSection(model)
                    controllerSection(model)
                    incidentSection(model)
                } }
.portalRootList()
                .refreshable { await model.loadDetails() }
            }
        }
    }

    private func alarmSection(_ model: SiteModel) -> some View {
        Section("Alarms") {
            if model.alarms.isEmpty {
                Label("No active alarms", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.alarms) { alarm in
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
            if model.unavailableControllerCount > 0 {
                Label("Controllers that could not be reached: \(model.unavailableControllerCount)", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func robotSection(_ model: SiteModel) -> some View {
        Section("Robots") {
            if model.robots.robotCount == 0 {
                Label("No robots reported", systemImage: "gearshape.2")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Online") { Text("\(model.robots.onlineCount) of \(model.robots.robotCount)") }
                if model.robots.errorCount > 0 {
                    LabeledContent("With errors") { Text("\(model.robots.errorCount)").foregroundStyle(Color.statusError) }
                }
            }
            ForEach(model.robots.robots.filter { $0.hasError || !$0.isOnline }) { robot in
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(robot.name)
                    } icon: {
                        Image(systemName: robot.hasError ? "exclamationmark.triangle.fill" : "wifi.slash")
                            .foregroundStyle(robot.hasError ? Color.statusError : Color.secondary)
                    }
                    Text(robot.errorText?.isEmpty == false ? robot.errorText! : String(localized: "Offline"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func controllerSection(_ model: SiteModel) -> some View {
        Section("Controllers") {
            if model.controllers.isEmpty {
                Label("No controllers at this site", systemImage: "server.rack")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.controllers) { controller in
                NavigationLink(value: controller) {
                    HStack(spacing: 10) {
                        Image(systemName: controller.isOnline ? "checkmark.circle" : "circle.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(controller.isOnline ? Text("Online") : Text("Offline"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(controller.comment?.isEmpty == false ? controller.comment! : controller.id)
                                .foregroundStyle(.primary)
                            if let version = controller.version {
                                Text(version).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func incidentSection(_ model: SiteModel) -> some View {
        Section("Incidents") {
            if model.incidents.isEmpty {
                Label("No incidents", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.incidents) { incident in
                NavigationLink(value: incident) {
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
        }
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
                LabeledContent("Status") {
                    Label(controller.isOnline ? "Online" : "Offline", systemImage: controller.isOnline ? "checkmark.circle" : "circle.slash")
                        .foregroundStyle(.secondary)
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
        .navigationTitle(controller.comment?.isEmpty == false ? controller.comment! : controller.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskAboutButton(viewing: Viewing(kind: "controller", id: controller.id), subject: controller.comment ?? controller.id)
                    .labelStyle(.iconOnly)
            }
        }
        .fullScreenCover(item: $screenSession) { screen in
            ControllerScreenView(session: screen, name: controller.comment ?? controller.id)
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
