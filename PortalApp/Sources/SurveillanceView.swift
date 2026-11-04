import Observation
import PortalKit
import SwiftUI

/// SurveillanceSnapshot is every camera the person can see, kept so coming back to the wall shows it at once.
struct SurveillanceSnapshot: Sendable {
    var cameras: [Camera] = []
}

/// SurveillanceModel holds the cameras of every site the person can see. More and the Sites tab read it to decide whether to offer the
/// wall, and the wall reads it to draw.
@MainActor
@Observable
final class SurveillanceModel {
    private(set) var cameras: [Camera] = []
    /// Whether the cameras were read at least once, so a row that waits for them is not offered or withdrawn too early.
    private(set) var hasLoaded = false
    private let connection: Connection
    private let cache: ResponseCache
    private let accountKey: String

    init(connection: Connection, cache: ResponseCache, accountKey: String) {
        self.connection = connection
        self.cache = cache
        self.accountKey = accountKey
    }

    var hasCameras: Bool { !cameras.isEmpty }

    func load(force: Bool = false) async throws {
        let key = CacheKey(accountKey: accountKey, name: "surveillanceCameras")
        try await cache.load(key, force: force, show: { (held: SurveillanceSnapshot) in
            cameras = held.cameras
            hasLoaded = true
        }, fetch: { [connection] in
            SurveillanceSnapshot(cameras: try await connection.allCameras())
        })
    }
}

/// SurveillanceView is the camera wall: every camera the person can see, in a section per site, with a filter by site and a search.
struct SurveillanceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    /// Whether the wall is the root of a tab, which keeps the tab bar. Pushed from a list it hides it.
    var isTabRoot = false
    @State private var phase = LoadPhase.loading
    @State private var searchText = ""
    @State private var selectedSiteIds: Set<String> = []
    @State private var budget = CameraWallBudget()

    @ScaledMetric(relativeTo: .body) private var minimumTileWidth: CGFloat = 170

    private var model: SurveillanceModel { session.surveillance }

    var body: some View {
        content
            .background(Color.portalPage)
            .navigationTitle("Surveillance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(isTabRoot ? .automatic : .hidden, for: .tabBar)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search cameras")
            .toolbar {
                if sites.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu }
                }
            }
            .task { await load() }
    }

    private var siteNames: [String: String] {
        var names = session.siteNames
        for site in session.staffSites.sites { names[site.id] = site.name ?? names[site.id] }
        return names
    }

    private var sites: [SurveillanceSite] {
        Surveillance.sites(of: model.cameras, siteNames: siteNames, organizationNames: session.organizationNames)
    }

    private func load(force: Bool = false) async {
        do {
            try await model.load(force: force)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load cameras", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await load(force: true) } }
            }
        case .loaded:
            wall
        }
    }

    private var wall: some View {
        let groups = Surveillance.group(
            cameras: model.cameras, siteNames: siteNames, organizationNames: session.organizationNames, selectedSiteIds: selectedSiteIds, query: searchText)
        let shown = groups.flatMap(\.cameras)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !shown.isEmpty {
                    Text("\(Surveillance.onlineCount(shown)) of \(shown.count) online")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        header(group)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 12, alignment: .top)], alignment: .leading, spacing: 16) {
                            ForEach(group.cameras) { camera in
                                NavigationLink(value: PortalRoute.camera(CameraTarget(camera: camera))) { CameraTile(camera: camera, budget: budget) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .overlay {
            if groups.isEmpty {
                if searchText.isEmpty && selectedSiteIds.isEmpty {
                    ContentUnavailableView("No cameras", systemImage: "video.slash", description: Text("The sites you can see have no cameras."))
                } else if searchText.isEmpty {
                    ContentUnavailableView("No cameras at these sites", systemImage: "video.slash")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .refreshable { await load(force: true) }
    }

    /// The site's name, with the organization's under it for a Mujin user, who sees many.
    private func header(_ group: SurveillanceGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.siteName ?? String(localized: "Unknown site"))
                .font(.headline)
                .foregroundStyle(.primary)
            if session.isStaff, let organizationName = group.organizationName {
                Text(organizationName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var filterMenu: some View {
        Menu {
            Button {
                selectedSiteIds = []
            } label: {
                if selectedSiteIds.isEmpty {
                    Label("All sites", systemImage: "checkmark")
                } else {
                    Text("All sites")
                }
            }
            ForEach(filterSections) { section in
                Section(section.title) {
                    ForEach(section.sites) { site in
                        Toggle(isOn: Binding(
                            get: { selectedSiteIds.contains(site.siteId) },
                            set: { isOn in
                                if isOn { selectedSiteIds.insert(site.siteId) } else { selectedSiteIds.remove(site.siteId) }
                            })
                        ) {
                            Text(site.siteName ?? String(localized: "Unknown site"))
                        }
                    }
                }
            }
        } label: {
            Label("Filter by site", systemImage: selectedSiteIds.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("surveillanceFilter")
    }

    /// The sites for the filter: under their organization's name for a Mujin user, in one list for anyone else.
    private var filterSections: [SurveillanceFilterSection] {
        guard session.isStaff else { return [SurveillanceFilterSection(title: String(localized: "Sites"), sites: sites)] }
        var order: [String] = []
        var grouped: [String: [SurveillanceSite]] = [:]
        for site in sites {
            let title = site.organizationName ?? String(localized: "Unknown organization")
            if grouped[title] == nil { order.append(title) }
            grouped[title, default: []].append(site)
        }
        return order.map { SurveillanceFilterSection(title: $0, sites: grouped[$0] ?? []) }
    }
}

/// SurveillanceFilterSection is the sites of one organization in the filter menu.
private struct SurveillanceFilterSection: Identifiable {
    let title: String
    let sites: [SurveillanceSite]
    var id: String { title }
}

/// SurveillanceRow is the row that opens the wall, in More and at the top of the Sites tab.
struct SurveillanceRow: View {
    var body: some View {
        Label("Surveillance", systemImage: "web.camera")
            .foregroundStyle(.primary)
    }
}
