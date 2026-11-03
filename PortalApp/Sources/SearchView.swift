import PortalKit
import SwiftUI

/// SearchModel is what the Search tab shows: the answer to the typed text, the suggested shortcuts for an empty field, and the
/// rows the person opened before.
@MainActor
@Observable
final class SearchModel {
    enum Phase: Equatable {
        /// Nothing typed yet, or less than a search needs.
        case idle
        case searching
        case results([GlobalSearchSection])
        case empty
        case failed(GlobalSearchFailure)
    }

    private(set) var phase = Phase.idle
    /// The shortcuts the server suggests for an empty field.
    private(set) var suggestions: [GlobalSearchResult] = []
    /// Whether the suggestions were asked for, so the empty field does not flash its hint before they arrive.
    private(set) var hasLoadedSuggestions = false
    /// Why the suggestions could not be read, when they could not.
    private(set) var suggestionsFailure: GlobalSearchFailure?
    private(set) var recents: [GlobalSearchResult] = []
    private let store = GlobalSearchRecents()

    /// Reads what was opened before. The demo shows invented rows and keeps nothing.
    func loadRecents(accountKey: String, isDemo: Bool) {
        recents = isDemo ? (SearchDemo.owns(ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"]) ? SearchDemo.recents : []) : store.load(accountKey: accountKey)
    }

    func loadSuggestions(connection: Connection, onError: @MainActor (Error) -> Void) async {
        do {
            suggestions = try await connection.globalSearch(query: "")
            suggestionsFailure = nil
        } catch {
            if Task.isCancelled { return }
            onError(error)
            suggestionsFailure = GlobalSearchFailure.classify(error)
        }
        hasLoadedSuggestions = true
    }

    func showIdle() {
        phase = .idle
    }

    /// Shows that a search is under way. Results already on the screen stay until the new ones replace them.
    func beginSearch() {
        if case .results = phase { return }
        phase = .searching
    }

    func search(_ text: String, connection: Connection, onError: @MainActor (Error) -> Void) async {
        do {
            let sections = GlobalSearchRules.sections(try await connection.globalSearch(query: text))
            if Task.isCancelled { return }
            phase = sections.isEmpty ? .empty : .results(sections)
        } catch {
            // A search the next keystroke replaced is not a failure.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            onError(error)
            phase = .failed(GlobalSearchFailure.classify(error))
        }
    }

    func remember(_ result: GlobalSearchResult, accountKey: String, isDemo: Bool) {
        if isDemo { return }
        recents = store.remember(result, accountKey: accountKey)
    }

    func clearRecents(accountKey: String) {
        store.clear(accountKey: accountKey)
        recents = []
    }
}

/// SearchTabView is the Search tab: one field that finds controllers, sites, tickets, people, chats and the rest, and jumps to
/// a page of settings. It asks the server the same question the Portal web app's palette asks, so both show the same rows.
struct SearchTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var model = SearchModel()
    @State private var query = SearchDemo.startingQuery

    private var text: String { GlobalSearchRules.normalized(query) }

    var body: some View {
        NavigationStack {
            content
                .background(Color.portalPage)
                .navigationTitle("Search")
                .scrollDismissesKeyboard(.interactively)
        }
        .searchable(text: $query, prompt: "Search or jump to a page")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: session.account.accountKey) {
            model.loadRecents(accountKey: session.account.accountKey, isDemo: appModel.isDemo)
            guard session.capabilities.offersGlobalSearch else { return }
            await model.loadSuggestions(connection: appModel.connection(for: session.account), onError: reportError)
        }
        .task(id: text) { await runSearch() }
    }

    private func reportError(_ error: Error) {
        appModel.handle(error, account: session.account)
    }

    private func runSearch() async {
        guard GlobalSearchRules.isSearching(text) else {
            model.showIdle()
            return
        }
        model.beginSearch()
        // The server is asked after a pause in typing.
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        await model.search(text, connection: appModel.connection(for: session.account), onError: reportError)
    }

    private func open(_ result: GlobalSearchResult) {
        model.remember(result, accountKey: session.account.accountKey, isDemo: appModel.isDemo)
        if let link = result.link {
            appModel.openedLink = OpenedLink(link: link, organizationId: result.organizationId)
        } else {
            // The app has no screen for it: the page opens in the browser, signed in.
            let address = session.account.server.endpoint(result.path)
            Task { await appModel.openInApp(address, account: session.account) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !session.capabilities.offersGlobalSearch {
            ContentUnavailableView {
                Label("Search is not available", systemImage: "magnifyingglass")
            } description: {
                Text("This server does not offer search yet.")
            }
        } else if GlobalSearchRules.isSearching(text) {
            searchContent
        } else {
            idleContent
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch model.phase {
        case .idle, .searching:
            ProgressView()
        case .results(let sections):
            List { PortalRows {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.results, id: \.rowKey) { result in row(result) }
                    } header: {
                        Text(localizedWords(section.group.title))
                    }
                }
            } }
            .portalRootList()
        case .empty:
            ContentUnavailableView {
                Label("No results", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing matches \u{201C}\(text)\u{201D}. Try another word, an id, or the name of a page.")
            }
        case .failed(let failure):
            failureView(failure) { Task { await runSearch() } }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if model.recents.isEmpty && model.suggestions.isEmpty {
            if let failure = model.suggestionsFailure, model.hasLoadedSuggestions {
                failureView(failure) { Task { await model.loadSuggestions(connection: appModel.connection(for: session.account), onError: reportError) } }
            } else if model.hasLoadedSuggestions {
                ContentUnavailableView {
                    Label("Search Portal", systemImage: "magnifyingglass")
                } description: {
                    Text("Find a controller, site, ticket, person, or a page of settings.")
                }
            } else {
                ProgressView()
            }
        } else {
            List { PortalRows {
                if !model.recents.isEmpty {
                    Section {
                        ForEach(model.recents, id: \.rowKey) { result in row(result) }
                    } header: {
                        HStack {
                            Text("Recent")
                            Spacer()
                            Button("Clear") { model.clearRecents(accountKey: session.account.accountKey) }
                                .textCase(nil)
                                .accessibilityIdentifier("clearRecentSearches")
                        }
                    }
                }
                if !model.suggestions.isEmpty {
                    Section {
                        ForEach(model.suggestions, id: \.rowKey) { result in row(result) }
                    } header: {
                        Text(localizedWords(GlobalSearchGroup.shortcut.title))
                    }
                }
            } }
            .portalRootList()
        }
    }

    @ViewBuilder
    private func failureView(_ failure: GlobalSearchFailure, retry: @escaping () -> Void) -> some View {
        switch failure {
        case .offline:
            ContentUnavailableView {
                Label("You are offline", systemImage: "wifi.slash")
            } description: {
                Text("Connect to the internet to search.")
            } actions: {
                Button("Try again", action: retry)
            }
        case .unavailable:
            ContentUnavailableView {
                Label("Search is not available", systemImage: "magnifyingglass")
            } description: {
                Text("This server does not offer search yet.")
            }
        case .other(let message):
            ContentUnavailableView {
                Label("Could not search", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again", action: retry)
            }
        }
    }

    private func row(_ result: GlobalSearchResult) -> some View {
        Button { open(result) } label: { SearchResultRow(result: result) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("searchRow-\(result.rowKey)")
    }
}

/// SearchResultRow is one result: a symbol for its kind, its name, one line of context, and the organization when the row is
/// outside the person's own.
private struct SearchResultRow: View {
    let result: GlobalSearchResult

    /// Whether the title is a name or an id, which must stay whole, and not a sentence, which wraps.
    private var isName: Bool {
        switch result.resultKind {
        case .ticket, .conversation, .incident, .page, .directChat, .groupChat: false
        default: true
        }
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                if isName {
                    Text(result.title).foregroundStyle(.primary).portalNameLine()
                } else {
                    Text(result.title).foregroundStyle(.primary)
                }
                if !result.subtitle.isEmpty {
                    Text(result.subtitle).font(.footnote).foregroundStyle(.secondary).portalNameLine()
                }
                if let organization = result.foreignOrganizationName {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2").imageScale(.small).accessibilityHidden(true)
                        Text(organization).portalNameLine()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: SearchSymbol.name(for: result)).foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// SearchSymbol picks the symbol of a row: from its kind, and for a shortcut from the name of the icon the server gives it.
enum SearchSymbol {
    static func name(for result: GlobalSearchResult) -> String {
        switch result.resultKind {
        case .shortcut: ShortcutSymbols.symbol(shortcutId: result.id, iconName: result.iconName, fallback: shortcut)
        case .controller: "server.rack"
        case .virtualController: "desktopcomputer"
        case .site: "building.2"
        case .cell: "square.grid.2x2"
        case .camera: "video"
        case .organization: "building.columns"
        case .person: "person"
        case .directChat: "bubble.left"
        case .groupChat: "bubble.left.and.bubble.right"
        case .conversation: "sparkles"
        case .ticket: "tray.full"
        case .release: "shippingbox"
        case .page: "doc.text"
        case .incident: "exclamationmark.shield"
        }
    }

    /// The server's fixed vocabulary of shortcut icons. A name this app does not know gets an arrow, so a newer server never leaves a gap.
    static func shortcut(_ iconName: String?) -> String {
        switch iconName ?? "" {
        case "overview": "house"
        case "dashboard": "chart.bar"
        case "materialFlow": "arrow.triangle.branch"
        case "surveillance": "video"
        case "incidents": "exclamationmark.shield"
        case "controllers": "server.rack"
        case "virtualControllers": "desktopcomputer"
        case "tickets": "tray.full"
        case "sites": "building.2"
        case "releases": "shippingbox"
        case "notifications": "bell"
        case "help": "questionmark.circle"
        case "commandLine": "terminal"
        case "assistant": "bubble.left.and.bubble.right"
        case "goals": "scope"
        case "ideas": "lightbulb"
        case "knowledge": "brain.head.profile"
        case "automations": "clock.arrow.2.circlepath"
        case "oversight": "eye"
        case "settings": "gearshape"
        case "profile": "person.crop.circle"
        case "activity": "clock.arrow.circlepath"
        case "preferences": "slider.horizontal.3"
        case "alarms": "bell.badge"
        case "sessions": "iphone"
        case "passkeys": "person.badge.key"
        case "tokens": "key"
        case "authorizedApps": "app.badge.checkmark"
        case "vpn": "lock.shield"
        case "ssh": "terminal"
        case "usage": "chart.bar.xaxis"
        case "providers": "cpu"
        case "agents": "person.crop.square"
        case "registrations": "person.badge.plus"
        case "grants": "key"
        case "emailTemplates": "envelope"
        case "plans": "tag"
        case "oauthClients": "person.badge.key"
        case "controllerUsage": "chart.xyaxis.line"
        case "organization": "building.2"
        case "members": "person.2"
        case "groups": "person.2.crop.square.stack"
        case "roles": "checkmark.shield"
        case "sso": "person.badge.key"
        case "domains": "globe"
        case "audit": "list.bullet.clipboard"
        case "billing": "creditcard"
        case "legal": "doc.plaintext"
        default: "arrow.right"
        }
    }
}
