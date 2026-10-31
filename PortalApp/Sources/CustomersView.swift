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
.portalList()
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

/// OrganizationDetailView is one customer: its sites and its tickets.
struct OrganizationDetailView: View {
    enum Part: String, CaseIterable, Identifiable {
        case sites
        case tickets
        var id: String { rawValue }
    }

    let organization: OrganizationSummary
    @State private var part = Part.sites

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $part) {
                Text("Sites").tag(Part.sites)
                Text("Tickets").tag(Part.tickets)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch part {
            case .sites:
                SiteView(organizationId: organization.id, embedsNavigation: false)
            case .tickets:
                TicketsView(organizationId: organization.id, embedsNavigation: false)
            }
        }
        .navigationTitle(organization.name ?? organization.id)
        .navigationBarTitleDisplayMode(.inline)
    }
}
