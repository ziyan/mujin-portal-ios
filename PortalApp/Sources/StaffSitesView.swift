import Observation
import PortalKit
import SwiftUI

/// StaffSitesSnapshot is what the staff Sites list shows, kept so coming back to it shows it at once.
struct StaffSitesSnapshot: Sendable {
    var sites: [SiteSummary] = []
    var organizationNames: [String: String] = [:]
}

/// StaffSitesView is the Sites tab for Mujin users: every site they can see, in a section per organization.
/// A row opens the same site screen a customer sees.
struct StaffSitesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var phase = LoadPhase.loading
    @State private var searchText = ""
    @State private var path: [PortalRoute] = []
    @State private var isLinking = false
    /// The organization whose people are shown in a sheet, from a section header.
    @State private var peopleOrganization: PeopleOrganization?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                content
            }
            .navigationTitle("Sites")
            .portalDestinations()
            .notificationsBell()
            .toolbar {
                if ControllerLinkAccess.canOffer(permissions: session.profile?.me.permissions ?? []) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isLinking = true } label: { Label("Link a controller", systemImage: "link.badge.plus") }
                    }
                }
            }
            .sheet(isPresented: $isLinking) { LinkControllerView() }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sites")
            .sheet(item: $peopleOrganization) { organization in
                PeopleSheet(organizationId: organization.id)
            }
            .task {
                await load()
                await openDemoScreen()
            }
        }
    }

    /// The demo walks the list into a site, then into its controllers, as a person would.
    private func load(force: Bool = false) async {
        do {
            try await session.loadStaffSites(force: force)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    private func openDemoScreen() async {
        guard appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("site-staff") || screen == "controllers-staff" || screen == "virtual-controllers-staff", path.isEmpty,
            let first = SiteGroups.group(session.staffSites.sites, organizationNames: session.staffSites.organizationNames).first?.sites.first,
            let organizationId = first.organizationId
        else { return }
        if screen == "controllers-staff" {
            path.append(.allControllers)
            return
        }
        if screen == "virtual-controllers-staff" {
            path.append(.allVirtualControllers)
            return
        }
        path.append(.site(id: first.id, organizationId: organizationId))
        if screen == "site-staff-controllers" {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            path.append(.siteList(.controllers, organizationKey: session.siteModel(for: organizationId, siteId: first.id).sessionKey))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load sites", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await load(force: true) } }
            }
        case .loaded:
            let groups = SiteGroups.group(session.staffSites.sites, organizationNames: session.staffSites.organizationNames, query: searchText)
            List {
                PortalRows {
                    if searchText.isEmpty {
                        Section {
                            NavigationLink(value: PortalRoute.allControllers) {
                                Label("All controllers", systemImage: "server.rack").foregroundStyle(.primary)
                            }
                            NavigationLink(value: PortalRoute.allVirtualControllers) {
                                Label("All virtual controllers", systemImage: "square.stack.3d.up").foregroundStyle(.primary)
                            }
                        }
                    }
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.sites) { site in
                                NavigationLink(value: PortalRoute.site(id: site.id, organizationId: group.organizationId)) {
                                    Label(site.name ?? site.id, systemImage: "building.2").foregroundStyle(.primary)
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.organizationName ?? String(localized: "Unknown organization"))
                                Spacer()
                                // The organization's people, for whoever may manage them.
                                if session.peopleAccess.hasPeopleScreens(in: group.organizationId) {
                                    Button {
                                        peopleOrganization = PeopleOrganization(id: group.organizationId)
                                    } label: {
                                        Label("People", systemImage: "person.2")
                                            .font(.footnote)
                                            .foregroundStyle(Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .portalRootList()
            .overlay {
                if groups.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("No sites", systemImage: "building.2")
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .refreshable { await load(force: true) }
        }
    }
}
