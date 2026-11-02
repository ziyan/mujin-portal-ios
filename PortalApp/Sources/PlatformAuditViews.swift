import PortalKit
import SwiftUI

/// AuditLogView is the audit log of an organization, or of every organization: newest first, a page at a time, narrowed by what was
/// done, how long ago, and a search of the address, request or resource.
struct AuditLogView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let organizationId: String?

    @State private var phase = LoadPhase.loading
    @State private var events: [AuditEvent] = []
    @State private var totalCount = 0
    @State private var filter = AuditFilter()
    @State private var searchText = ""
    @State private var isLoadingMore = false
    @State private var actions = ActionState()

    var body: some View {
        content
            .navigationTitle("Audit log")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search address, request or resource")
            .onSubmit(of: .search) { filter.searchText = searchText }
            .onChange(of: searchText) { _, text in
                if text.isEmpty, !filter.searchText.isEmpty { filter.searchText = "" }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { filterMenu } }
            .task(id: filter) { await reload() }
            .failureAlert(actions)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load the audit log", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await reload() } }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            PortalRows {
                Section {
                    ForEach(events) { event in
                        NavigationLink(value: MoreDestination.platform(.auditEvent(event))) { AuditEventRow(event: event) }
                    }
                } footer: {
                    if !events.isEmpty { Text("\(events.count) of \(totalCount) shown") }
                }
                if events.count < totalCount {
                    Section {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack {
                                Text("Load more")
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                if isLoadingMore { ProgressView() }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingMore)
                    }
                }
            }
        }
        .portalList()
        .overlay {
            if events.isEmpty {
                if filter.isFiltering {
                    ContentUnavailableView("No matching entries", systemImage: "line.3.horizontal.decrease.circle", description: Text("Nothing in the log matches these filters."))
                } else {
                    ContentUnavailableView("Nothing logged yet", systemImage: "list.bullet.clipboard")
                }
            }
        }
        .refreshable { await reload() }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Time range", selection: $filter.range) {
                Text("Any time").tag(AuditRange.anyTime)
                Text("Last 24 hours").tag(AuditRange.lastDay)
                Text("Last 7 days").tag(AuditRange.lastWeek)
                Text("Last 30 days").tag(AuditRange.lastMonth)
            }
            Section("What was done") {
                ForEach(AuditFilter.actionNames, id: \.self) { name in
                    Toggle(
                        isOn: Binding(
                            get: { filter.actions.contains(name) },
                            set: { isOn in
                                if isOn { filter.actions.insert(name) } else { filter.actions.remove(name) }
                            })
                    ) {
                        Text(actionTitle(name))
                    }
                }
            }
            if filter.isFiltering {
                Button("Clear filters", role: .destructive) {
                    filter = AuditFilter()
                    searchText = ""
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("auditFilter")
    }

    private func actionTitle(_ name: String) -> LocalizedStringKey {
        switch name {
        case "create": return "Created"
        case "update": return "Changed"
        default: return "Deleted"
        }
    }

    private func reload() async {
        do {
            let page = try await appModel.connection(for: session.account).auditEvents(organizationId: organizationId, filter: filter)
            events = page.events
            totalCount = page.totalCount
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if phase == .loading { phase = .failed(error.userMessage) } else { actions.errorMessage = error.userMessage }
        }
    }

    private func loadMore() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await appModel.connection(for: session.account).auditEvents(organizationId: organizationId, filter: filter, offset: events.count)
            let known = Set(events.map(\.id))
            events += page.events.filter { !known.contains($0.id) }
            totalCount = page.totalCount
        } catch {
            appModel.handle(error, account: session.account)
            actions.errorMessage = error.userMessage
        }
    }
}

extension AuditSummary {
    /// The sentence in the person's language: the verb and the noun are looked up apart, so each has its own translation. Anything the
    /// catalog does not know stays in English.
    var localized: String {
        String(format: String(localized: String.LocalizationValue(verbFormat)), String(localized: String.LocalizationValue(noun)))
    }
}

/// AuditEventRow is one entry of the log in a list: what was done to what, by whom and when.
struct AuditEventRow: View {
    let event: AuditEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.summary.localized)
                .foregroundStyle(Color.primary)
            Text(event.resourceName)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
            Text("\(event.actorName), \(event.createdDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            if !event.changes.isEmpty {
                Text("^[\(event.changes.count) field](inflect: true) changed")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// AuditEventView is one entry of the log in full: who, from where, and every field it changed from what to what.
struct AuditEventView: View {
    let event: AuditEvent

    var body: some View {
        List {
            PortalRows {
                Section {
                    fact("Done", event.summary.localized)
                    fact("Resource", event.resourceName)
                    if let when = event.createdDate { fact("When", when.formatted(date: .complete, time: .standard)) }
                }
                Section("Who") {
                    fact("Actor", event.actorName)
                    if let kind = event.actorType, !kind.isEmpty { fact("Kind", kind.prefix(1).uppercased() + kind.dropFirst()) }
                    if let address = event.sourceIp, !address.isEmpty { fact("Address", address) }
                    if let device = DeviceDescription.name(userAgent: event.userAgent) { fact("Device", device) }
                }
                if !event.changes.isEmpty {
                    Section("Changes") {
                        ForEach(event.changes) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.field)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                                if !change.beforeText.isEmpty {
                                    Text(change.beforeText)
                                        .foregroundStyle(Color.statusError)
                                        .strikethrough()
                                        .textSelection(.enabled)
                                }
                                if !change.afterText.isEmpty {
                                    Text(change.afterText)
                                        .foregroundStyle(Color.statusSuccess)
                                        .textSelection(.enabled)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if hasRequestDetails {
                    Section("Request") {
                    if let route = event.requestRoute, !route.isEmpty {
                        fact("Route", [event.requestMethod, route].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                    }
                    if let request = event.requestId, !request.isEmpty { fact("Request", request) }
                    if let identifier = event.resourceId, !identifier.isEmpty { fact("Resource ID", identifier) }
                    }
                }
            }
        }
        .portalList()
        .navigationTitle("Audit entry")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasRequestDetails: Bool {
        [event.requestRoute, event.requestId, event.resourceId].contains { !($0 ?? "").isEmpty }
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            Text(value)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
