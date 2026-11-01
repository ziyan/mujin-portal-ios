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
        .searchable(text: $searchText, prompt: "Search releases")
        .task { await load() }
    }

    private var shown: [Release] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return releases }
        return releases.filter { $0.displayName.localizedCaseInsensitiveContains(text) || ($0.versionString ?? "").localizedCaseInsensitiveContains(text) }
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
                if let channel = release.channel, !channel.isEmpty { ReleaseBadge(text: channel) }
                if release.status != "published" { ReleaseBadge(text: release.status ?? "") }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ReleaseBadge: View {
    let text: String

    var body: some View {
        Text(text.capitalized)
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
    let releaseId: String
    @State private var release: Release?
    @State private var controllers: [ControllerSummary] = []
    @State private var virtualControllers: [VirtualControllerSummary] = []
    @State private var phase = LoadPhase.loading

    private static let shownCount = 10

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
        .task { await load() }
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
                Section { MarkdownView(markdown: description) }
            }
            if let changelog = release.changelogText(preferredLanguages: languages) {
                Section("What changed") { MarkdownView(markdown: changelog) }
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
                    if controllers.count > Self.shownCount { Text("And \(controllers.count - Self.shownCount) more").foregroundStyle(.secondary) }
                }
            }
            if !virtualControllers.isEmpty {
                Section("Virtual controllers") {
                    ForEach(virtualControllers.prefix(Self.shownCount)) { virtual in
                        NavigationLink(value: PortalRoute.virtualController(virtual)) { Text(virtual.displayName).foregroundStyle(.primary) }
                    }
                    if virtualControllers.count > Self.shownCount { Text("And \(virtualControllers.count - Self.shownCount) more").foregroundStyle(.secondary) }
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
    }
}
