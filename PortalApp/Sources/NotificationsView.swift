import Observation
import PortalKit
import SwiftUI

/// NotificationsBell is the bell in a tab's navigation bar, with the number
/// of entries not read yet.
struct NotificationsBell: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        Button {
            session.isShowingNotifications = true
        } label: {
            Label("Notifications", systemImage: session.unreadCount > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityValue(session.unreadCount > 0 ? Text("\(session.unreadCount) unread") : Text(""))
        .accessibilityIdentifier("notificationsBell")
    }
}

extension View {
    /// Puts the bell in the leading corner of the navigation bar.
    func notificationsBell() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { NotificationsBell() }
        }
    }
}

/// NotificationsModel loads the inbox.
@MainActor
@Observable
final class NotificationsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var items: [PortalNotification] = []
    /// Whether what was already read is listed too, which only the person asks for.
    var showsPast = false
    let cache: ResponseCache?
    let accountKey: String

    init(connection: Connection, cache: ResponseCache? = nil, accountKey: String = "", onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.cache = cache
        self.accountKey = accountKey
        self.onError = onError
    }

    private var cacheKey: CacheKey { CacheKey(accountKey: accountKey, name: showsPast ? "notifications-all" : "notifications-unread") }

    func load(force: Bool = false) async {
        if let cache, let held = cache.hit(cacheKey, as: [PortalNotification].self) {
            items = held.value
            phase = .loaded
            if held.isFresh && !force { return }
        }
        do {
            var rows = try await connection.notifications(status: "unread")
            if showsPast { rows += try await connection.notifications(status: "read") }
            items = rows
            cache?.store(items, for: cacheKey)
            phase = .loaded
        } catch {
            onError(error)
            if items.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    func togglePast() async {
        showsPast.toggle()
        await load()
    }

    func markRead(_ item: PortalNotification) async {
        guard item.isUnread else { return }
        do {
            try await connection.markNotificationRead(id: item.id)
            // The row changes in place from the result, in the list and in the cache.
            let readAt = ISO8601DateFormatter().string(from: Date())
            func marked(_ rows: inout [PortalNotification]) {
                rows = rows.map { $0.id == item.id ? $0.markedRead(at: readAt) : $0 }
            }
            marked(&items)
            cache?.update(cacheKey, as: [PortalNotification].self) { marked(&$0) }
        } catch {
            onError(error)
        }
    }

    func markAllRead() async {
        do {
            try await connection.markAllNotificationsRead()
            let readAt = ISO8601DateFormatter().string(from: Date())
            items = items.map { $0.markedRead(at: readAt) }
            let updated = items
            cache?.store(updated, for: cacheKey)
        } catch {
            onError(error)
        }
    }
}

/// NotificationsView is the inbox, as a sheet over whichever tab is in front.
struct NotificationsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: NotificationsModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("notificationsClose")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task {
                                await model?.markAllRead()
                                await session.refreshUnreadCount()
                            }
                        } label: {
                            Label("Mark all as read", systemImage: "checkmark.circle")
                        }
                        NavigationLink {
                            NotificationPreferencesView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            let inbox = NotificationsModel(
                connection: appModel.connection(for: session.account), cache: session.cache, accountKey: session.account.accountKey,
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            inbox.showsPast = DemoOptions.screen == "notifications-past"
            model = inbox
            await inbox.load()
        }
        // A notification created while the inbox is open appears without pulling.
        .onChange(of: session.notificationRevision) { _, _ in
            Task { await model?.load(force: true) }
        }
    }

    @ViewBuilder
    private func content(_ model: NotificationsModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load notifications", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing new", systemImage: "bell")
                } description: {
                    Text("Tickets, alarms and incidents that need you show up here.")
                } actions: {
                    pastButton(model)
                }
            } else {
                List {
                    ForEach(model.items) { item in
                        Button {
                            open(item, model: model)
                        } label: {
                            NotificationRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.portalCard)
                    }
                    pastButton(model)
                        .listRowBackground(Color.portalCard)
                }
                .portalList()
                .refreshable { await model.load(force: true) }
            }
        }
    }

    private func pastButton(_ model: NotificationsModel) -> some View {
        Button(model.showsPast ? LocalizedStringKey("Hide past notifications") : LocalizedStringKey("Show past notifications")) {
            Task { await model.togglePast() }
        }
        .accessibilityIdentifier("notificationsPastToggle")
    }

    private func open(_ item: PortalNotification, model: NotificationsModel) {
        Task {
            await model.markRead(item)
            await session.refreshUnreadCount()
        }
        switch item.target {
        case .ticket(let id):
            session.ticketToOpen = id
            session.selectedSection = .tickets
        case .incident:
            // Staff read incidents under More; customers see them on their site's page.
            if session.isStaff {
                session.incidentsRequested = true
                session.selectedSection = .more
            } else {
                session.selectedSection = .site
            }
        case .site:
            session.selectedSection = .site
        case .chat(let conversationId):
            session.chatToOpen = conversationId
            session.selectedSection = .assistant
        case .conversation(let id):
            session.open(.conversation(id: id))
        case .goal(let id):
            session.open(.goal(id: id))
        case .automations:
            session.automationsRequested = true
            session.selectedSection = .more
        case .none:
            return
        }
        dismiss()
    }
}

private struct NotificationRow: View {
    let item: PortalNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.isUnread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                sentence
                    .font(.body.weight(item.isUnread ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if let detail = item.detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if let date = item.date {
                    Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.isUnread ? Text("Not read yet") : Text(""))
    }

    @ViewBuilder
    private var sentence: some View {
        switch item.kind {
        case "ticket_comment": Text("New comment on \(item.subject)")
        case "ticket_assigned": Text("Assigned to you: \(item.subject)")
        case "ticket_mentioned": Text("You were mentioned on \(item.subject)")
        case "ticket_lifecycle": Text("Status changed on \(item.subject)")
        case "ticket_activity": Text("Activity on \(item.subject)")
        case "incident": Text("Incident: \(item.subject)")
        case "alarm": Text("Alarm: \(item.subject)")
        case "chat_message": Text(item.subject)
        case "agent_message": Text("The assistant wrote to you: \(item.subject)")
        case "agent_waiting":
            if item.agentWaitingKind == "approval" {
                Text("The assistant is waiting for your approval to use \(item.agentWaitingToolName ?? "").")
            } else {
                Text("The assistant has a question for you.")
            }
        case "agent_goal_needs_you": Text("A goal needs you: \(item.subject)")
        case "budget_alert": Text("Your budget needs attention")
        case "agent_job_failed":
            if item.isAgentJobPaused == true {
                Text("Your job \(item.subject) was paused after repeated failures.")
            } else {
                Text("A run of your job \(item.subject) failed.")
            }
        default: Text(item.subject)
        }
    }
}

/// NotificationPreferencesView chooses which kinds of notification reach
/// the phone and the inbox box, and which are mailed.
struct NotificationPreferencesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @State private var preferences = NotificationPreferences()
    @State private var isLoaded = false
    @State private var errorText: String?

    var body: some View {
        Form { PortalRows {
            Section {
                Text("Notifications always show in the app. Choose which ones also reach this phone, and which are mailed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(NotificationPreferences.kinds, id: \.self) { kind in
                Section {
                    Toggle(isOn: binding(kind: kind, channel: "push")) { Label("Push", systemImage: "bell.badge").foregroundStyle(.primary) }
                    // The assistant's notifications and chat messages have no email.
                    if !kind.hasPrefix("agent_") && kind != "chat_message" {
                        Toggle(isOn: binding(kind: kind, channel: "email")) { Label("Email", systemImage: "envelope").foregroundStyle(.primary) }
                    }
                } header: {
                    Label(Self.title(kind), systemImage: Self.symbol(kind))
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(Color.statusError) }
            }
        } }
.portalList()
        .navigationTitle("Notification settings")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(!isLoaded)
        .task {
            do {
                preferences = try await appModel.connection(for: session.account).notificationPreferences()
            } catch {
                errorText = error.userMessage
            }
            isLoaded = true
        }
    }

    private func binding(kind: String, channel: String) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(kind: kind, channel: channel) },
            set: { newValue in
                let before = preferences
                preferences.set(kind: kind, channel: channel, isEnabled: newValue)
                Task {
                    do {
                        try await appModel.connection(for: session.account).setNotificationPreference(kind: kind, channel: channel, isEnabled: newValue)
                        errorText = nil
                    } catch {
                        preferences = before
                        errorText = error.userMessage
                    }
                }
            })
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "ticket_comment": "text.bubble"
        case "ticket_assigned": "person.badge.plus"
        case "ticket_mentioned": "at"
        case "ticket_lifecycle", "ticket_activity": "tray.full"
        case "incident": "exclamationmark.triangle"
        case "alarm": "bell.badge"
        case "budget_alert": "dollarsign.circle"
        case "agent_job_failed": "clock.badge.exclamationmark"
        case "chat_message": "bubble.left"
        case "agent_message": "sparkles"
        case "agent_waiting": "questionmark.bubble"
        case "agent_goal_needs_you": "scope"
        default: "bell"
        }
    }

    static func title(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "ticket_comment": "Comments on tickets"
        case "ticket_assigned": "Tickets assigned to me"
        case "ticket_mentioned": "Mentions"
        case "ticket_lifecycle": "Ticket status changes"
        case "ticket_activity": "Other ticket activity"
        case "incident": "Incidents"
        case "alarm": "Alarms"
        case "budget_alert": "Budget alerts"
        case "agent_job_failed": "Failed assistant jobs"
        case "chat_message": "Chat messages"
        case "agent_message": "Messages from the assistant"
        case "agent_waiting": "Questions and approvals waiting for me"
        case "agent_goal_needs_you": "Goals that need me"
        default: LocalizedStringKey(kind)
        }
    }
}
