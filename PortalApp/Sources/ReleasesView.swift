import PortalKit
import SwiftUI

/// ReleaseRow is a controller's release in a detail list: the release's name, and whether
/// the controller matches it exactly or by version only. It opens the release.
struct ReleaseRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let release: ControllerRelease
    @State private var name: String?
    @State private var versionString: String?

    var body: some View {
        switch release {
        case .notLinked:
            LabeledContent("Release") { Text("Not linked").foregroundStyle(.secondary) }
        case .versionOnly(let id), .exact(let id):
            NavigationLink(value: PortalRoute.release(id: id)) {
                LabeledContent("Release") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(name ?? id).foregroundStyle(.primary)
                        if let versionString, !versionString.isEmpty {
                            Text(versionString).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task(id: id) {
                let key = CacheKey(accountKey: session.account.accountKey, name: "release", variables: id)
                if let held = session.cache.hit(key, as: Release.self) {
                    name = held.value.displayName
                    versionString = held.value.versionString
                    if held.isFresh { return }
                }
                if let fetched = try? await appModel.connection(for: session.account).release(id: id) {
                    session.cache.store(fetched, for: key)
                    name = fetched.displayName
                    versionString = fetched.versionString
                }
            }
        }
    }
}

/// ReleasesView is the releases under More, newest first, for browsing their notes.
struct ReleasesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var releases: [Release] = []
    @State private var phase = LoadPhase.loading
    @State private var searchText = ""
    @State private var filter = ReleaseFilter()

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load releases", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load(force: true) } }
                }
            case .loaded:
                if shown.isEmpty {
                    ContentUnavailableView("No releases", systemImage: "shippingbox")
                } else {
                    List(shown) { release in
                        NavigationLink(value: PortalRoute.release(id: release.id)) { ReleaseListRow(release: release) }
                            .listRowBackground(Color.portalCard)
                    }
                    .portalList()
                    .refreshable { await load(force: true) }
                }
            }
        }
        .navigationTitle("Releases")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search releases")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Application", selection: $filter.application) {
                        Text("All applications").tag(String?.none)
                        ForEach(ReleaseFilter.applications(in: releases), id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("Channel", selection: $filter.channel) {
                        Text("All channels").tag(String?.none)
                        ForEach(ReleaseFilter.channels(in: releases), id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Toggle("Show withdrawn", isOn: $filter.showsWithdrawn)
                } label: {
                    Label("Filter", systemImage: filter.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("releaseFilter")
            }
        }
        .task { await load() }
    }

    private var shown: [Release] {
        var active = filter
        active.query = searchText
        return active.apply(releases)
    }

    private func load(force: Bool = false) async {
        let key = CacheKey(accountKey: session.account.accountKey, name: "releases")
        do {
            try await session.cache.load(key, force: force, show: { (held: [Release]) in
                releases = held
                phase = .loaded
            }, fetch: { try await appModel.connection(for: session.account).releases() })
        } catch {
            appModel.handle(error, account: session.account)
            if releases.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

private struct ReleaseListRow: View {
    let release: Release

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(release.displayName).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: 8)
                if let date = release.date {
                    Text(date, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let version = release.versionString, !version.isEmpty, version != release.displayName { Text(version).font(.subheadline).foregroundStyle(.secondary) }
                if let channel = release.channel, !channel.isEmpty { ReleaseBadge(text: channel, isVerbatim: true) }
                if release.status != "published" { ReleaseBadge(text: release.status ?? "") }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ReleaseBadge: View {
    let text: String
    /// A channel is shown as the server names it, as the web does; a status is capitalized.
    var isVerbatim = false

    var body: some View {
        Text(isVerbatim ? text : text.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// ReleaseDetailView is one release: what it is, its description and the notes of what changed in the
/// person's language (English when there is none), and the controllers and virtual controllers on it.
struct ReleaseDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var releaseId: String
    @State private var release: Release?
    @State private var controllers: [ControllerSummary] = []
    @State private var virtualControllers: [VirtualControllerSummary] = []
    @State private var tickets: [Ticket] = []
    @State private var neighbors: (newer: Release?, older: Release?) = (nil, nil)
    @State private var phase = LoadPhase.loading

    private static let shownCount = 5

    init(releaseId: String) {
        _releaseId = State(initialValue: releaseId)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this release", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load(force: true) } }
                }
            case .loaded:
                if let release { content(release) }
            }
        }
        .navigationTitle(release?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            // Newer and older releases, in the order of the list, replace this page in place.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { if let newer = neighbors.newer { releaseId = newer.id } } label: { Label("Newer release", systemImage: "chevron.up") }
                    .disabled(neighbors.newer == nil)
                Button { if let older = neighbors.older { releaseId = older.id } } label: { Label("Older release", systemImage: "chevron.down") }
                    .disabled(neighbors.older == nil)
            }
        }
        .task(id: releaseId) { await load() }
    }

    private func content(_ release: Release) -> some View {
        let languages = Locale.preferredLanguages
        return List { PortalRows {
            Section {
                if let version = release.versionString, !version.isEmpty { LabeledContent("Version") { Text(version) } }
                if let application = release.application, !application.isEmpty { LabeledContent("Application") { Text(application) } }
                if let channel = release.channel, !channel.isEmpty { LabeledContent("Channel") { Text(channel.capitalized) } }
                LabeledContent("Status") { Text(LocalizedStringKey(release.status ?? "")) }
                if let date = release.date { LabeledContent("Released") { Text(date, format: .dateTime.month().day().year()) } }
            }
            if let description = release.descriptionText(preferredLanguages: languages) {
                Section { RichBodyView(markdown: description, connection: appModel.connection(for: session.account)) }
            }
            if let changelog = release.changelogText(preferredLanguages: languages) {
                Section("What changed") { RichBodyView(markdown: changelog, connection: appModel.connection(for: session.account)) }
            }
            if !controllers.isEmpty {
                Section("Controllers") {
                    ForEach(controllers.prefix(Self.shownCount)) { controller in
                        NavigationLink(value: PortalRoute.controller(controller)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(controller.displayName).foregroundStyle(.primary)
                                if let detail = controller.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if controllers.count > Self.shownCount {
                        NavigationLink(value: PortalRoute.releaseUsers(id: releaseId, kind: .controllers)) { Text("See all \(controllers.count)").foregroundStyle(.tint) }
                    }
                }
            }
            if !virtualControllers.isEmpty {
                Section("Virtual controllers") {
                    ForEach(virtualControllers.prefix(Self.shownCount)) { virtual in
                        NavigationLink(value: PortalRoute.virtualController(virtual)) { Text(virtual.displayName).foregroundStyle(.primary) }
                    }
                    if virtualControllers.count > Self.shownCount {
                        NavigationLink(value: PortalRoute.releaseUsers(id: releaseId, kind: .virtualControllers)) { Text("See all \(virtualControllers.count)").foregroundStyle(.tint) }
                    }
                }
            }
            if !tickets.isEmpty {
                Section("Tickets") {
                    ForEach(tickets.prefix(Self.shownCount)) { ticket in
                        NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                    }
                    if tickets.count > Self.shownCount {
                        NavigationLink(value: PortalRoute.releaseUsers(id: releaseId, kind: .tickets)) { Text("See all \(tickets.count)").foregroundStyle(.tint) }
                    }
                }
            }
            if let images = release.images, !images.isEmpty {
                Section("Images") {
                    ForEach(images.prefix(Self.shownCount)) { image in
                        NavigationLink(value: PortalRoute.releaseImage(id: image.id)) { ReleaseImageRow(image: image) }
                    }
                    if images.count > Self.shownCount {
                        NavigationLink(value: PortalRoute.releaseUsers(id: releaseId, kind: .images)) { Text("See all \(images.count)").foregroundStyle(.tint) }
                    }
                }
            }
        } }
        .portalList()
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        let connection = appModel.connection(for: session.account)
        let key = CacheKey(accountKey: session.account.accountKey, name: "release", variables: releaseId)
        do {
            try await session.cache.load(key, force: force, show: { (held: Release) in
                release = held
                phase = .loaded
            }, fetch: { try await connection.release(id: releaseId) })
        } catch {
            appModel.handle(error, account: session.account)
            if release == nil { phase = .failed(error.userMessage) }
            return
        }
        // Who runs it: a failure here leaves the lists empty rather than failing the page.
        controllers = (try? await connection.controllers(usingRelease: releaseId)) ?? controllers
        virtualControllers = (try? await connection.virtualControllers(usingRelease: releaseId)) ?? virtualControllers
        tickets = (try? await connection.tickets(usingRelease: releaseId)) ?? tickets
        if let list = session.cache.hit(CacheKey(accountKey: session.account.accountKey, name: "releases"), as: [Release].self)?.value {
            neighbors = ReleaseFilter.neighbors(of: releaseId, in: ReleaseFilter().apply(list))
        }
    }
}

/// ReleaseImageRow is one image of a release: its tag, and the version and preset it was built for.
struct ReleaseImageRow: View {
    let image: Release.Image

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(image.tag ?? image.id).foregroundStyle(.primary).lineLimit(1)
            let detail = [image.labelVersion, image.labelPreset, image.labelProject].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
            if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// ReleaseImageView is one image of a release with the labels a controller is matched on.
struct ReleaseImageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let imageId: String
    @State private var image: ReleaseImageDetail?
    @State private var phase = LoadPhase.loading

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this image", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if let image {
                    List { PortalRows {
                        Section {
                            if let tag = image.tag, !tag.isEmpty { LabeledContent("Tag") { Text(tag) } }
                            if let repository = image.repository, !repository.isEmpty { LabeledContent("Repository") { Text(repository).lineLimit(2) } }
                            if let digest = image.digest, !digest.isEmpty { LabeledContent("Digest") { Text(digest).font(.footnote.monospaced()).lineLimit(2) } }
                        }
                        Section("Labels") {
                            ForEach(image.labelRows, id: \.name) { row in
                                LabeledContent(LocalizedStringKey(row.name)) { Text(row.value).multilineTextAlignment(.trailing) }
                            }
                        }
                    } }
                    .portalList()
                }
            }
        }
        .navigationTitle(image?.tag ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await load() }
    }

    private func load() async {
        do {
            image = try await appModel.connection(for: session.account).releaseImage(id: imageId)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if image == nil { phase = .failed(error.userMessage) }
        }
    }
}

/// ReleaseUsersView is the full list behind a "See all": the controllers, virtual controllers, tickets or images of a release.
struct ReleaseUsersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let releaseId: String
    let kind: ReleaseUsageKind
    @State private var controllers: [ControllerSummary] = []
    @State private var virtualControllers: [VirtualControllerSummary] = []
    @State private var tickets: [Ticket] = []
    @State private var images: [Release.Image] = []
    @State private var searchText = ""
    @State private var isLoading = true

    var body: some View {
        List { PortalRows {
            switch kind {
            case .controllers:
                ForEach(controllers.filter(matches)) { controller in
                    NavigationLink(value: PortalRoute.controller(controller)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(controller.displayName).foregroundStyle(.primary)
                            if let detail = controller.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
            case .virtualControllers:
                ForEach(virtualControllers.filter { searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText) }) { virtual in
                    NavigationLink(value: PortalRoute.virtualController(virtual)) { Text(virtual.displayName).foregroundStyle(.primary) }
                }
            case .tickets:
                ForEach(tickets.filter { searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText) }) { ticket in
                    NavigationLink(value: PortalRoute.ticket(id: ticket.id)) { TicketRow(ticket: ticket) }
                }
            case .images:
                ForEach(images.filter { searchText.isEmpty || ($0.tag ?? "").localizedCaseInsensitiveContains(searchText) }) { image in
                    NavigationLink(value: PortalRoute.releaseImage(id: image.id)) { ReleaseImageRow(image: image) }
                }
            }
        } }
        .portalList()
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await load() }
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .controllers: "Controllers"
        case .virtualControllers: "Virtual controllers"
        case .tickets: "Tickets"
        case .images: "Images"
        }
    }

    private func matches(_ controller: ControllerSummary) -> Bool {
        searchText.isEmpty || controller.displayName.localizedCaseInsensitiveContains(searchText) || (controller.detail ?? "").localizedCaseInsensitiveContains(searchText)
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        switch kind {
        case .controllers: controllers = (try? await connection.controllers(usingRelease: releaseId)) ?? []
        case .virtualControllers: virtualControllers = (try? await connection.virtualControllers(usingRelease: releaseId)) ?? []
        case .tickets: tickets = (try? await connection.tickets(usingRelease: releaseId)) ?? []
        case .images: images = (try? await connection.release(id: releaseId))?.images ?? []
        }
        isLoading = false
    }
}

