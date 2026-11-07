import PortalKit
import SwiftUI

/// SitePageIcon is the symbol a page is given in the web app, or a page symbol when it has none.
struct SitePageIcon: View {
    let icon: String?

    var body: some View {
        if let symbol = icon?.trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty {
            Text(symbol)
        } else {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
        }
    }
}

/// SitePageDraftBadge marks a page that readers cannot see yet.
struct SitePageDraftBadge: View {
    var body: some View {
        Text("Draft")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.statusWarning.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.statusWarning)
            .accessibilityIdentifier("sitePageDraftBadge")
    }
}

/// SitePageRowLabel is one page in a list: its symbol, its title and a mark when it is a draft.
private struct SitePageRowLabel: View {
    let page: SitePage
    var subtitle: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(page.listTitle.isEmpty ? String(localized: "Untitled") : page.listTitle).foregroundStyle(.primary)
                    if page.isDraft { SitePageDraftBadge() }
                }
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
        } icon: {
            SitePageIcon(icon: page.icon)
        }
    }
}

/// SitePagesView is the documentation pages of a site as a tree: each page with the pages inside it, in the order the web shows.
/// The site may belong to another organization than the person's own (a Mujin user looking at a customer), so it is read by its id.
struct SitePagesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let siteId: String

    @State private var pages: [SitePage] = []
    @State private var site: SiteSummary?
    @State private var phase = LoadPhase.loading
    /// The pages shown open in the tree. The demo opens the first branch to photograph it.
    @State private var expandedIds: Set<String> = DemoOptions.screen == "site-pages-expanded" ? ["page01", "page03"] : []
    @State private var isMissing = false
    @State private var query = ""
    @State private var isCreating = false
    @State private var createdPage: SitePage?

    private var connection: Connection { appModel.connection(for: session.account) }

    /// Whether the person may add a page: the site says so, and until it is read the pages do.
    private var canCreate: Bool {
        guard session.capabilities.offersSitePageEditing else { return false }
        return site?.can("page:edit") ?? pages.contains { $0.canEdit }
    }

    private var canPublish: Bool { site?.can("page:publish") ?? pages.contains { $0.canPublish } }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                failedView(message)
            case .loaded:
                if pages.isEmpty { emptyView } else { listView }
            }
        }
        .navigationTitle("Documentation")
        .navigationSubtitle(site?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
        .toolbar {
            if canCreate, phase == .loaded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCreating = true } label: { Label("New page", systemImage: "plus") }
                        .accessibilityIdentifier("sitePageNewButton")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            SitePageCreateView(
                siteId: siteId, parentPageId: nil, siblings: SitePageTree.children(of: nil, in: pages), canPublish: canPublish
            ) { created in
                pages.append(created)
                createdPage = created
            }
        }
        .navigationDestination(item: $createdPage) { created in
            SitePageView(siteId: siteId, pageId: created.id)
        }
        .task(id: siteId) {
            await load()
            // The demo's new page screen opens the sheet a moment after the tree is drawn, since the demo closes sheets as it loads.
            if appModel.isDemo, DemoOptions.screen == "site-pages-new" {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                isCreating = true
            }
        }
        .onAppear {
            // Coming back from a page, which may have been changed there.
            if phase == .loaded { Task { await load() } }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No pages yet", systemImage: "doc.text")
        } description: {
            Text(LocalizedStringKey(canCreate ? "Add the first page of this site's documentation." : "Pages written for this site show up here."))
        } actions: {
            if canCreate { Button("New page") { isCreating = true } }
        }
    }

    @ViewBuilder
    private func failedView(_ message: String) -> some View {
        if isMissing {
            ContentUnavailableView {
                Label("Documentation not found", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("This site may have been removed, or you may not have access to it.")
            } actions: {
                Button("Open on the web") { openOnTheWeb() }
            }
        } else {
            ContentUnavailableView {
                Label("Could not load the documentation", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await load() } }
                Button("Open on the web") { openOnTheWeb() }
            }
        }
    }

    private var listView: some View {
        let nodes = SitePageTree.nodes(pages)
        let matches = SitePageTree.matches(pages, query: query)
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return List {
            PortalRows {
                if isSearching {
                    if matches.isEmpty {
                        Section { Text("No page has that in its title.").foregroundStyle(.secondary) }
                    } else {
                        Section {
                            ForEach(matches) { page in
                                NavigationLink(value: PortalRoute.sitePage(id: page.id, siteId: siteId)) {
                                    SitePageRowLabel(page: page, subtitle: parentTitles(of: page))
                                }
                                .accessibilityIdentifier("sitePageRow-\(page.id)")
                            }
                        }
                    }
                } else {
                    Section {
                        SitePageTreeRows(nodes: nodes, siteId: siteId, expandedIds: $expandedIds)
                    }
                }
            }
        }
        .portalList()
        .accessibilityIdentifier("sitePagesList")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search pages")
        .refreshable { await load() }
    }

    /// The pages above a page, as "Guides / Setup".
    private func parentTitles(of page: SitePage) -> String {
        SitePageTree.ancestorIds(of: page.id, in: pages).reversed().compactMap { ancestorId in
            pages.first { $0.id == ancestorId }?.listTitle
        }.joined(separator: " / ")
    }

    private func openOnTheWeb() {
        WebPage(appModel: appModel, session: session).open(PortalLink.sitePages(siteId: siteId).path)
    }

    private func load() async {
        let connection = connection
        let siteId = siteId
        do {
            async let loadedSite = try? connection.siteForPages(id: siteId)
            let loaded = try await connection.sitePages(siteId: siteId)
            // A page made here may not be in the answer yet, which a replica can send a moment behind the change.
            let kept = pages.filter { page in !loaded.contains { $0.id == page.id } && page.id == createdPage?.id }
            pages = loaded + kept
            site = await loadedSite
            isMissing = false
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            guard pages.isEmpty else { return }
            isMissing = SitePageRules.isNotFound(error)
            phase = .failed(error.userMessage)
        }
    }
}

/// SitePageView is one documentation page: its title and words, laid out as the chat and the tickets lay out theirs, the pages inside
/// it, and its history. A person who may edit pages can change it or add a page inside it.
struct SitePageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let siteId: String
    let pageId: String

    @State private var page: SitePage?
    @State private var revision: SitePageRevision?
    @State private var treePages: [SitePage] = []
    @State private var phase = LoadPhase.loading
    @State private var isMissing = false
    @State private var revisionFailure: String?
    @State private var isEditing = false
    @State private var isAddingPage = false
    @State private var addedPage: SitePage?
    @State private var isLinkCopied = false

    private var connection: Connection { appModel.connection(for: session.account) }
    private var canEdit: Bool { (page?.canEdit ?? false) && session.capabilities.offersSitePageEditing }
    private var childPages: [SitePage] { SitePageTree.children(of: pageId, in: treePages) }

    private var ancestorPages: [SitePage] {
        SitePageTree.ancestorIds(of: pageId, in: treePages).reversed().compactMap { ancestorId in treePages.first { $0.id == ancestorId } }
    }

    private var barTitle: String {
        guard let page else { return "" }
        let title = page.shownTitle(revision: revision)
        return title.isEmpty ? String(localized: "Untitled") : title
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                failedView(message)
            case .loaded:
                if let page { content(page) }
            }
        }
        .navigationTitle(barTitle)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
        .toolbar {
            if let page, phase == .loaded {
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isEditing = true } label: { Label("Edit", systemImage: "square.and.pencil") }
                            .accessibilityIdentifier("sitePageEditButton")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DetailMenu(demoScreen: "site-page-menu") {
                        LinkMenuItems(link: .sitePage(id: page.id, siteId: siteId), isCopied: $isLinkCopied)
                        if canEdit {
                            Button { isAddingPage = true } label: { Label("New page inside", systemImage: "plus") }
                        }
                        Button { openOnTheWeb() } label: { Label("Open on the web", systemImage: "safari") }
                    }
                }
            }
        }
        .linkCopiedToast($isLinkCopied)
        .demoMenuHost(screen: "site-page-menu")
        .sheet(isPresented: $isEditing) {
            if let page {
                SitePageEditView(page: page, revision: revision) { saved, madeRevision in
                    apply(saved, madeRevision: madeRevision)
                }
            }
        }
        .sheet(isPresented: $isAddingPage) {
            if let page {
                SitePageCreateView(siteId: page.siteId ?? siteId, parentPageId: page.id, siblings: childPages, canPublish: page.canPublish) { created in
                    treePages.append(created)
                    addedPage = created
                }
            }
        }
        .navigationDestination(item: $addedPage) { created in
            SitePageView(siteId: siteId, pageId: created.id)
        }
        .task(id: pageId) {
            await load()
            // The demo's edit screen opens the editor a moment after the page is drawn, since the demo closes sheets as it loads.
            if appModel.isDemo, DemoOptions.screen == "site-page-edit", canEdit {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                isEditing = true
            }
        }
    }

    // MARK: states

    @ViewBuilder
    private func failedView(_ message: String) -> some View {
        if isMissing {
            ContentUnavailableView {
                Label("Page not found", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("It may have been deleted or moved, or you may not have access to it. Open it on the web to check.")
            } actions: {
                Button("Open on the web") { openOnTheWeb() }
                    .accessibilityIdentifier("sitePageOpenOnTheWeb")
            }
            .accessibilityIdentifier("sitePageNotFound")
        } else {
            ContentUnavailableView {
                Label("Could not load this page", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await load() } }
                Button("Open on the web") { openOnTheWeb() }
            }
        }
    }

    private static let historyRowScrollID = "sitePageHistoryRow"

    /// The demo's table screen starts at the end of the page, where a long table offers the rest of its rows.
    private func scrollToEndInDemo(_ proxy: ScrollViewProxy) async {
        guard appModel.isDemo, DemoOptions.screen == "site-page-table-end" else { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        proxy.scrollTo(Self.historyRowScrollID, anchor: .bottom)
    }

    private func content(_ page: SitePage) -> some View {
        let words = SitePageRules.wordsBelowTitle(page.shownContent(revision: revision), title: page.shownTitle(revision: revision))
        return ScrollViewReader { proxy in List {
            PortalRows {
                Section { header(page) }
                Section {
                    if page.showsRevision, revision == nil {
                        if let revisionFailure {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Could not load the content of this page.")
                                Text(revisionFailure).font(.footnote).foregroundStyle(.secondary)
                                Button("Try again") { Task { await loadRevision(of: page) } }
                            }
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    } else if words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("This page has no content yet.").foregroundStyle(.secondary)
                        if canEdit { Button("Edit") { isEditing = true } }
                    } else {
                        RichBodyView(markdown: words, connection: connection)
                            .accessibilityIdentifier("sitePageWords")
                    }
                }
                if !childPages.isEmpty {
                    Section("Pages inside") {
                        ForEach(childPages) { child in
                            NavigationLink(value: PortalRoute.sitePage(id: child.id, siteId: siteId)) { SitePageRowLabel(page: child) }
                                .accessibilityIdentifier("sitePageChild-\(child.id)")
                        }
                    }
                }
                if page.showsRevision {
                    Section {
                        NavigationLink(value: PortalRoute.sitePageHistory(siteId: siteId, page: page)) {
                            Label("History", systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                        }
                        .id(Self.historyRowScrollID)
                        .accessibilityIdentifier("sitePageHistoryRow")
                    }
                }
                if canEdit {
                    OnTheWebRow(
                        title: "Move or delete on the web", explanation: "Moving, deleting and restoring pages, and adding pictures, are done in Portal on the web.",
                        path: PortalLink.sitePage(id: page.id, siteId: siteId).path)
                }
            }
        }
        .portalList()
        .refreshable { await load() }
        .task { await scrollToEndInDemo(proxy) }
        }
    }

    private func header(_ page: SitePage) -> some View {
        let title = page.shownTitle(revision: revision)
        return VStack(alignment: .leading, spacing: 8) {
            if !ancestorPages.isEmpty {
                Text(ancestorPages.map { $0.listTitle.isEmpty ? String(localized: "Untitled") : $0.listTitle }.joined(separator: " / "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SitePageIcon(icon: page.icon)
                Text(title.isEmpty ? String(localized: "Untitled") : title)
                    .font(.title2.bold())
                    .accessibilityIdentifier("sitePageTitle")
                if page.isDraft { SitePageDraftBadge() }
            }
            if page.isDraft, canEdit {
                Text("Only people who can edit pages see this draft. Publish it to show it to readers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let date = page.modifiedDate {
                Text("Edited \(date, format: .relative(presentation: .named))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: actions

    private func openOnTheWeb() {
        WebPage(appModel: appModel, session: session).open(PortalLink.sitePage(id: pageId, siteId: siteId).path)
    }

    /// Shows what a save or a publish answered with. It is not read back: a replica can send the old page for a moment.
    private func apply(_ saved: SitePage, madeRevision: SitePageRevision?) {
        page = saved
        if let madeRevision { revision = madeRevision }
        treePages = treePages.map { $0.id == saved.id ? saved : $0 }
    }

    private func load() async {
        let connection = connection
        let pageId = pageId
        do {
            let loaded = try await connection.sitePage(id: pageId)
            page = loaded
            isMissing = false
            phase = .loaded
            async let tree = try? connection.sitePages(siteId: loaded.siteId ?? siteId)
            if loaded.showsRevision { await loadRevision(of: loaded) } else { revision = nil }
            if let found = await tree { treePages = found }
        } catch {
            appModel.handle(error, account: session.account)
            guard page == nil else { return }
            isMissing = SitePageRules.isNotFound(error)
            phase = .failed(error.userMessage)
        }
    }

    private func loadRevision(of page: SitePage) async {
        guard let revisionId = page.currentRevisionId, !revisionId.isEmpty else { return }
        revisionFailure = nil
        do {
            revision = try await connection.sitePageRevision(id: revisionId)
        } catch {
            appModel.handle(error, account: session.account)
            if revision == nil { revisionFailure = error.userMessage }
        }
    }
}

/// SitePageHistoryView lists the published versions of a page, newest first. It is read only: restoring one is done on the web.
struct SitePageHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let siteId: String
    let page: SitePage

    @State private var revisions: [SitePageRevision] = []
    @State private var phase = LoadPhase.loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load the history", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if revisions.isEmpty {
                    ContentUnavailableView {
                        Label("No history yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("A version is kept each time the page is published.")
                    }
                } else {
                    list
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
        .task { await load() }
    }

    private var list: some View {
        List {
            PortalRows {
                Section {
                    ForEach(revisions) { entry in
                        NavigationLink(
                            value: PortalRoute.sitePageRevision(siteId: siteId, pageId: page.id, revision: entry, isCurrent: entry.id == page.currentRevisionId)
                        ) {
                            revisionRow(entry)
                        }
                        .accessibilityIdentifier("sitePageRevisionRow-\(entry.id)")
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private func revisionRow(_ entry: SitePageRevision) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Version \(Int(entry.revisionNumber ?? 0))").font(.body.weight(.semibold)).foregroundStyle(.primary)
                if entry.id == page.currentRevisionId { SitePageCurrentBadge() }
            }
            if let summary = entry.summary, !summary.isEmpty { Text(summary).font(.subheadline).foregroundStyle(.primary) }
            if let date = entry.date {
                Text(verbatim: "\(session.name(ofPerson: entry.authorUserId)), \(date.formatted(.dateTime.month().day().year().hour().minute()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            revisions = try await appModel.connection(for: session.account).sitePageRevisions(pageId: page.id)
            phase = .loaded
            await session.loadPeople(revisions.compactMap(\.authorUserId))
        } catch {
            appModel.handle(error, account: session.account)
            if revisions.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// SitePageCurrentBadge marks the version of a page that readers see now.
private struct SitePageCurrentBadge: View {
    var body: some View {
        Text("Current")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.statusSuccess.opacity(0.18), in: Capsule())
            .foregroundStyle(Color.statusSuccess)
    }
}

/// SitePageRevisionView is one earlier version of a page, to read and not to change.
struct SitePageRevisionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let siteId: String
    let pageId: String
    let revision: SitePageRevision
    let isCurrent: Bool

    var body: some View {
        List {
            PortalRows {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(revision.title?.isEmpty == false ? (revision.title ?? "") : String(localized: "Untitled"))
                            .font(.title2.bold())
                            .accessibilityIdentifier("sitePageRevisionTitle")
                        Text(LocalizedStringKey(isCurrent ? "This is the version readers see. It is read only here." : "An earlier version. It is read only here."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let summary = revision.summary, !summary.isEmpty { Text(summary).font(.subheadline) }
                    }
                    .padding(.vertical, 2)
                }
                Section {
                    if (revision.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("This version has no content.").foregroundStyle(.secondary)
                    } else {
                        RichBodyView(
                            markdown: SitePageRules.wordsBelowTitle(revision.content ?? "", title: revision.title ?? ""),
                            connection: appModel.connection(for: session.account))
                    }
                }
                if !isCurrent {
                    OnTheWebRow(
                        title: "Restore on the web", explanation: "Restoring an earlier version is done in Portal on the web.",
                        path: PortalLink.sitePage(id: pageId, siteId: siteId).path)
                }
            }
        }
        .portalList()
        .navigationTitle("Version \(Int(revision.revisionNumber ?? 0))")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
    }
}

/// SitePageTreeRows is pages with the pages inside them, which open under the page. Tapping a row opens the page; the arrow opens the
/// pages inside it.
private struct SitePageTreeRows: View {
    let nodes: [SitePageNode]
    let siteId: String
    @Binding var expandedIds: Set<String>

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: isExpanded(node)) {
                    SitePageTreeRows(nodes: children, siteId: siteId, expandedIds: $expandedIds)
                } label: {
                    row(node)
                }
            } else {
                row(node)
            }
        }
    }

    private func row(_ node: SitePageNode) -> some View {
        NavigationLink(value: PortalRoute.sitePage(id: node.id, siteId: siteId)) { SitePageRowLabel(page: node.page) }
            .accessibilityIdentifier("sitePageRow-\(node.id)")
    }

    private func isExpanded(_ node: SitePageNode) -> Binding<Bool> {
        Binding(
            get: { expandedIds.contains(node.id) },
            set: { isOpen in
                if isOpen {
                    expandedIds.insert(node.id)
                } else {
                    expandedIds.remove(node.id)
                }
            })
    }
}
