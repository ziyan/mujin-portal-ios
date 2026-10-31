import Observation
import PortalKit
import SwiftUI

/// CustomersView is the Customers tab for Mujin users: the organizations,
/// to pick one before looking at its sites and tickets.
struct CustomersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var organizations: [OrganizationSummary] = []
    @State private var phase = AutomationsModel.Phase.loading
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not load customers", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                case .loaded:
                    List(shown) { organization in
                        NavigationLink(value: organization) {
                            Label {
                                Text(organization.name ?? organization.id)
                            } icon: {
                                Image(systemName: organization.isMujin == true ? "building.columns" : "building.2")
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        }
.listRowBackground(Color.portalCard)
}
.portalRootList()
                    .overlay {
                        if shown.isEmpty { ContentUnavailableView.search(text: searchText) }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Customers")
            .notificationsBell()
            .searchable(text: $searchText, prompt: "Search customers")
            .navigationDestination(for: OrganizationSummary.self) { organization in
                OrganizationDetailView(organization: organization)
            }
            .task { await load() }
        }
    }

    private var shown: [OrganizationSummary] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return organizations }
        return organizations.filter { ($0.name ?? "").localizedCaseInsensitiveContains(text) }
    }

    private func load() async {
        do {
            organizations = try await appModel.connection(for: session.account).organizations()
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if organizations.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// OrganizationDetailView is one customer: its sites, with its tickets a row away in the toolbar.
struct OrganizationDetailView: View {
    let organization: OrganizationSummary
    @State private var isShowingTickets = false

    var body: some View {
        SiteView(organizationId: organization.id, embedsNavigation: false)
            .navigationTitle(organization.name ?? organization.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TicketsView(organizationId: organization.id, embedsNavigation: false)
                    } label: {
                        Label("Tickets", systemImage: "tray.full")
                    }
                }
            }
    }
}
