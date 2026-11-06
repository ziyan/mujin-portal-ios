import PortalKit
import SwiftUI

/// AllControllersView lists every controller a Mujin user can see, with a search over id, comment and site, and a site filter.
struct AllControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var controllers: [ControllerSummary] = []
    @State private var phase = LoadPhase.loading
    @State private var filter = ControllerFilter()
    @State private var cells: [SiteCell] = []
    @State private var cellId: String?

    private var siteNames: [String: String] {
        Dictionary(session.staffSites.sites.map { ($0.id, $0.name ?? $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load controllers", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load(force: true) } }
                }
            case .loaded:
                let shown = filter.apply(controllers, siteNames: siteNames)
                List { PortalRows {
                    ForEach(shown) { controller in
                        NavigationLink(value: PortalRoute.controller(controller)) {
                            HStack(spacing: 10) {
                                Image(systemName: controller.isOnline ? "checkmark.circle" : "circle.slash")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(controller.isOnline ? Text("Online") : Text("Offline"))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(controller.displayName).foregroundStyle(.primary)
                                    if let detail = controller.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                                    if let name = siteNames[controller.siteId ?? ""] { Text(name).font(.footnote).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                } }
                .portalList()
                .overlay { if shown.isEmpty { ContentUnavailableView.search(text: filter.query) } }
                .refreshable { await load(force: true) }
            }
        }
        .navigationTitle("Controllers")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
        .searchable(text: $filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search controllers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !cells.isEmpty {
                        Picker("Cell", selection: $cellId) {
                            Text("All cells").tag(String?.none)
                            ForEach(cells) { cell in Text(cell.name ?? cell.id).tag(Optional(cell.id)) }
                        }
                    }
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
        // The cells of the chosen site narrow the list further.
        .task(id: filter.siteId) {
            cellId = nil
            filter.cellControllerIds = nil
            guard let siteId = filter.siteId else { cells = []; return }
            cells = (try? await appModel.connection(for: session.account).cells(siteId: siteId)) ?? []
        }
        .onChange(of: cellId) { _, id in
            filter.cellControllerIds = id.flatMap { id in cells.first { $0.id == id } }.map { Set($0.controllerIds ?? []) }
        }
    }

    private func load(force: Bool = false) async {
        let key = CacheKey(accountKey: session.account.accountKey, name: "allControllers")
        do {
            try await session.cache.load(key, force: force, show: { (held: [ControllerSummary]) in
                controllers = held
                phase = .loaded
            }, fetch: { [connection = appModel.connection(for: session.account)] in try await connection.controllers() })
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if controllers.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}
