import PortalKit
import SwiftUI

/// MemoryPageReference names a page to open: by id, or by the path in a
/// citation (the server prefers the person's own pool, then site,
/// organization and global), and a fact to point at.
struct MemoryPageReference: Hashable, Identifiable {
    var pageId: String?
    var path: String?
    var scope: String?
    var siteId: String?
    var factNumber: Int?

    var id: String { "\(pageId ?? "")|\(path ?? "")|\(scope ?? "")|\(factNumber ?? 0)" }
}

extension MemoryPage {
    var scopeTitle: LocalizedStringKey {
        switch memoryScope {
        case "user": "About you"
        case "site": "Sites"
        case "organization": "Your organization"
        case "global": "Everyone"
        default: LocalizedStringKey(memoryScope ?? "")
        }
    }
}

/// KnowledgeView is what the assistant remembers: pages by pool, with search.
struct KnowledgeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var pages: [MemoryPage] = []
    @State private var phase = LoadPhase.loading
    @State private var searchText = ""
    @State private var foundFacts: [MemoryFact] = []

    private static let scopeOrder = ["user", "site", "organization", "global"]

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load what the assistant knows", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("What it knows")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search what it knows")
        .task { await load() }
        .task(id: searchText) {
            if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
            if Task.isCancelled { return }
            await load()
        }
    }

    private var list: some View {
        List {
            PortalRows {
                if pages.isEmpty, foundFacts.isEmpty {
                    Section {
                        Text(searchText.isEmpty ? "The assistant has not remembered anything yet. It files what matters after your conversations." : "Nothing matches.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !foundFacts.isEmpty {
                    Section("Facts") {
                        ForEach(foundFacts) { fact in
                            NavigationLink(value: MoreDestination.memoryPage(MemoryPageReference(path: fact.pagePath, scope: fact.memoryScope, siteId: fact.siteId, factNumber: fact.number))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.sentence ?? "").foregroundStyle(.primary)
                                    Text(fact.shownPageName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(groups, id: \.scope) { group in
                    Section(group.pages[0].scopeTitle) {
                        ForEach(group.pages) { page in
                            NavigationLink(value: MoreDestination.memoryPage(MemoryPageReference(pageId: page.id))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(page.shownName).foregroundStyle(.primary)
                                    if let summary = page.summary, !summary.isEmpty {
                                        Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    if let count = page.liveFactCount, count > 0 {
                                        Text("\(count) facts").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .portalList()
        .refreshable { await load() }
    }

    private var groups: [(scope: String, pages: [MemoryPage])] {
        let grouped = Dictionary(grouping: pages) { $0.memoryScope ?? "" }
        return grouped.keys.sorted {
            (Self.scopeOrder.firstIndex(of: $0) ?? 99) < (Self.scopeOrder.firstIndex(of: $1) ?? 99)
        }.map { ($0, grouped[$0] ?? []) }
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        do {
            if searchText.isEmpty {
                pages = try await connection.memoryPages()
                foundFacts = []
            } else {
                let found = try await connection.searchMemory(searchText)
                pages = found.pages
                foundFacts = found.facts
            }
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if pages.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// MemoryPageView is one page: its summary, the facts that are still true,
/// the history, the links and the revisions. A fact the model could not find
/// its quote for is tagged Inferred.
struct MemoryPageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let reference: MemoryPageReference

    @State private var page: MemoryPage?
    @State private var revisions: [MemoryRevision] = []
    @State private var phase = LoadPhase.loading
    @State private var showsHistory = false
    @State private var forgetting: MemoryFact?
    @State private var isAddingFact = false
    @State private var newFact = ""
    @State private var editing: MemoryFact?
    @State private var editedSentence = ""
    @State private var errorText: String?

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load this page", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                if let page { content(page) }
            }
        }
        .navigationTitle(page?.shownName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Forget this fact?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget it", role: .destructive) {
                if let fact = forgetting { Task { await forget(fact) } }
            }
        } message: {
            Text("The assistant stops knowing it. This cannot be undone.")
        }
        .alert("Edit this fact", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Fact", text: $editedSentence)
            Button("Save") { if let fact = editing { Task { await save(fact) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add a fact", isPresented: $isAddingFact) {
            TextField("What should it remember?", text: $newFact)
            Button("Add") { Task { await add() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func content(_ page: MemoryPage) -> some View {
        let facts = page.facts ?? []
        let live = facts.filter(\.isLive)
        let history = facts.filter { !$0.isLive }
        return ScrollViewReader { proxy in
            List {
                PortalRows {
                    if let summary = page.summary, !summary.isEmpty {
                        Section { Text(summary) }
                    }
                    Section("What it knows") {
                        if live.isEmpty { Text("Nothing is current on this page.").foregroundStyle(.secondary) }
                        ForEach(live) { fact in
                            FactRow(fact: fact, isPointedAt: fact.number == reference.factNumber, canChange: page.isWritableByReader == true)
                                .id(fact.id)
                                .swipeActions {
                                    if page.isWritableByReader == true {
                                        Button("Forget", role: .destructive) { forgetting = fact }
                                        Button("Edit") {
                                            editedSentence = fact.sentence ?? ""
                                            editing = fact
                                        }
                                    }
                                }
                        }
                        if page.isWritableByReader == true {
                            Button { isAddingFact = true } label: { Label("Add a fact", systemImage: "plus") }
                        }
                    }
                    if let links = page.links, !links.isEmpty {
                        Section("Linked pages") {
                            ForEach(links) { link in
                                NavigationLink(value: MoreDestination.memoryPage(MemoryPageReference(pageId: link.fromMemoryPageId == page.id ? link.toMemoryPageId : link.fromMemoryPageId))) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(linkedName(link, from: page)).foregroundStyle(.primary)
                                        if link.linkStatus == "proposed" { Text("proposed").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                    }
                    if !history.isEmpty || !revisions.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showsHistory) {
                                ForEach(history) { fact in
                                    Text(fact.sentence ?? "").foregroundStyle(.secondary)
                                }
                                ForEach(revisions) { revision in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(revision.changeReason ?? revision.revisionKind ?? "").font(.footnote)
                                        if let date = PortalDate.parse(revision.createdAt) {
                                            Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } label: {
                                Text("History")
                            }
                        }
                    }
                    if let errorText { Section { Text(errorText).foregroundStyle(Color.statusError) } }
                }
            }
            .portalList()
            .refreshable { await load() }
            .onAppear {
                if let number = reference.factNumber, let target = live.first(where: { $0.number == number }) {
                    withAnimation { proxy.scrollTo(target.id, anchor: .center) }
                }
            }
        }
    }

    private func linkedName(_ link: MemoryLink, from page: MemoryPage) -> String {
        let isFrom = link.fromMemoryPageId == page.id
        return isFrom ? MemoryPageName.shown(name: link.toPageName, path: link.toPagePath) : MemoryPageName.shown(name: link.fromPageName, path: link.fromPagePath)
    }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        do {
            let loaded = try await connection.memoryPage(id: reference.pageId, path: reference.path, scope: reference.scope, siteId: reference.siteId)
            page = loaded
            phase = .loaded
            revisions = (try? await connection.memoryRevisions(pageId: loaded.id)) ?? []
        } catch {
            appModel.handle(error, account: session.account)
            if page == nil { phase = .failed(error.userMessage) }
        }
    }

    private func forget(_ fact: MemoryFact) async {
        do {
            try await appModel.connection(for: session.account).forgetMemoryFact(id: fact.id)
            forgetting = nil
            await load()
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }

    private func save(_ fact: MemoryFact) async {
        let sentence = editedSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        do {
            try await appModel.connection(for: session.account).editMemoryFact(id: fact.id, sentence: sentence)
            await load()
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }

    private func add() async {
        let sentence = newFact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, let page, let path = page.path else { return }
        do {
            try await appModel.connection(for: session.account).addMemoryFact(path: path, sentence: sentence, scope: page.memoryScope ?? "user", siteId: page.siteId)
            newFact = ""
            await load()
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}

private struct FactRow: View {
    let fact: MemoryFact
    let isPointedAt: Bool
    let canChange: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.sentence ?? "")
            HStack(spacing: 6) {
                if fact.isInferred == true {
                    Text("Inferred")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let quote = fact.evidence?.first?.quote, !quote.isEmpty {
                Text("\u{201C}\(quote)\u{201D}").font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

/// MemoryCitationSheet opens the page an answer cited, pointing at the fact.
struct MemoryCitationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let citation: MemoryCitation

    var body: some View {
        NavigationStack {
            MemoryPageView(reference: MemoryPageReference(path: citation.path, factNumber: citation.number))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .navigationDestination(for: MoreDestination.self) { destination in
                    if case .memoryPage(let reference) = destination { MemoryPageView(reference: reference) }
                }
        }
    }
}
