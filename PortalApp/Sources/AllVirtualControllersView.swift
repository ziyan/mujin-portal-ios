import PortalKit
import SwiftUI

/// AllVirtualControllersView lists every virtual controller a Mujin user can see, with a search and a site filter.
struct AllVirtualControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var rows: [VirtualControllerSummary] = []
    @State private var phase = LoadPhase.loading
    @State private var filter = VirtualControllerFilter()

    private var siteNames: [String: String] {
        Dictionary(session.staffSites.sites.map { ($0.id, $0.name ?? $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load virtual controllers", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load(force: true) } }
                }
            case .loaded:
                let shown = filter.apply(rows, siteNames: siteNames)
                List { PortalRows {
                    ForEach(shown) { virtual in
                        NavigationLink(value: PortalRoute.virtualController(virtual)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(virtual.displayName).foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(virtual.isRunning ? LocalizedStringKey("Running") : LocalizedStringKey(virtual.status ?? ""))
                                    if let name = siteNames[virtual.siteId ?? ""] { Text(name) }
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } }
                .portalList()
                .overlay { if shown.isEmpty { ContentUnavailableView.search(text: filter.query) } }
                .refreshable { await load(force: true) }
            }
        }
        .navigationTitle("Virtual controllers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search virtual controllers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Site", selection: $filter.siteId) {
                        Text("All sites").tag(String?.none)
                        ForEach(session.staffSites.sites.filter { $0.isArchived != true }.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }) { site in
                            Text(site.name ?? site.id).tag(Optional(site.id))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filter.siteId == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task {
            try? await session.loadStaffSites()
            await load()
        }
    }

    private func load(force: Bool = false) async {
        let key = CacheKey(accountKey: session.account.accountKey, name: "allVirtualControllers")
        do {
            try await session.cache.load(key, force: force, show: { (held: [VirtualControllerSummary]) in
                rows = held
                phase = .loaded
            }, fetch: { [connection = appModel.connection(for: session.account)] in try await connection.allVirtualControllers() })
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if rows.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}
