import PortalKit
import SwiftUI

/// ChatsView is the Chats tab: the person's chats with colleagues, with
/// unread counts, and a way to start a direct chat or a group.
struct ChatsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var model: ChatListModel?
    @State private var selection = SplitSelection()
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = DemoOptions.isListHidden ? .detailOnly : .automatic
    @State private var newChatMode: NewChatMode?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: Binding(
            get: { selection.isDetailOnTop ? .detail : .sidebar },
            set: { selection.setDetailOnTop($0 == .detail) })
        ) {
            Group {
                if !session.capabilities.offersChats {
                    ContentUnavailableView {
                        Label("Chats are not on this server yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Chats with colleagues arrive with a Portal update.")
                    }
                } else if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Chats")
            .notificationsBell()
            .searchable(text: $searchText, prompt: "Search chats")
            .toolbar {
                if session.capabilities.offersChats {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { newChatMode = .direct } label: { Label("New chat", systemImage: "person") }
                            Button { newChatMode = .group } label: { Label("New group", systemImage: "person.2.crop.square.stack") }
                        } label: {
                            Label("New chat", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("newChatButton")
                    }
                }
            }
            // The floating tab bar has the one sidebar button; the split view's own beside it would be a second. The list
            // still slides in from the leading edge.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if let shownConversationId = selection.detailId {
                NavigationStack {
                    ChatView(account: account, conversationId: shownConversationId, chatId: model?.chats.first { $0.id == shownConversationId }?.chatId)
                }
                .id(shownConversationId)
            } else {
                ContentUnavailableView("Select a chat", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .sheet(item: $newChatMode) { mode in
            NewChatView(mode: mode) { conversationId in
                selection.open(conversationId)
                Task { await model?.didStart(conversationId: conversationId) }
            }
        }
        .task(id: account.accountKey) {
            guard session.capabilities.offersChats else { return }
            let list = ChatListModel(
                connection: appModel.connection(for: account), onError: { [appModel, account] error in appModel.handle(error, account: account) })
            model = list
            await list.load()
            await session.refreshChatUnread()
            if appModel.isDemo, let screen = DemoOptions.screen {
                if screen.hasPrefix("chat:") { selection.open(String(screen.dropFirst("chat:".count))) }
                if screen == "chat-info" { selection.open("chatconv02") }
                if screen == "chat-site-info" || screen == "chat-site-picker" { selection.open("chatsite01") }
                if screen == "chat-reply" || screen == "chat-internal" || screen == "chat-internal-on" || screen == "chat-composer" || screen == "chat-mention" || screen == "chat-add-people" || screen == "chat-link-tap" || screen == "chat-links" || screen == "chat-message-actions" { selection.open("chatconv01") }
                if let conversationId = CallDemo.conversationId(for: screen) { selection.open(conversationId) }
                if let conversationId = SpeechDemo.conversationId(for: screen), conversationId.hasPrefix("chat") { selection.open(conversationId) }
                if screen == "chats-new" { newChatMode = .direct }
                if screen == "chats-new-group" { newChatMode = .group }
            }
        }
        .task(id: searchText) {
            if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
            if Task.isCancelled { return }
            await model?.search(searchText)
        }
        .onChange(of: session.lastReadChat) { _, mark in
            guard let mark, let model else { return }
            model.markRead(id: mark.conversationId)
            if model.searchText.isEmpty { session.setChatUnreadCount(model.unreadCount) }
        }
        .onChange(of: session.chatToOpen, initial: true) { _, conversationId in
            guard let conversationId else { return }
            selection.open(conversationId)
            session.chatToOpen = nil
            Task { await model?.load() }
        }
        .onChange(of: selection.selectedId) { _, _ in
            Task {
                await model?.load()
                await session.refreshChatUnread()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ChatListModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load chats", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            if model.chats.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start a chat with a colleague.")
                    } actions: {
                        Button("New chat") { newChatMode = .direct }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else {
                List(selection: $selection.selectedId) {
                    let people = model.chats.filter { $0.chat?.hasManyAuthors != true }
                    let groups = model.chats.filter { $0.chat?.isGroup == true }
                    let sites = model.chats.filter { $0.chat?.isSite == true }
                    if !people.isEmpty {
                        Section("People") {
                            ForEach(people) { conversation in
                                NavigationLink(value: conversation.id) { if let room = conversation.chat { ChatRow(room: room) } }
                                    .listRowBackground(Color.portalCard)
                            }
                        }
                    }
                    if !groups.isEmpty {
                        Section("Groups") {
                            ForEach(groups) { conversation in
                                NavigationLink(value: conversation.id) { if let room = conversation.chat { ChatRow(room: room) } }
                                    .listRowBackground(Color.portalCard)
                            }
                        }
                    }
                    if !sites.isEmpty {
                        Section("Sites") {
                            ForEach(sites) { conversation in
                                NavigationLink(value: conversation.id) { if let room = conversation.chat { ChatRow(room: room) } }
                                    .listRowBackground(Color.portalCard)
                            }
                        }
                    }
                }
.portalRootList()
                .refreshable {
                    await model.load()
                    await session.refreshChatUnread()
                }
            }
        }
    }
}

private struct ChatRow: View {
    let room: ChatRoom
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ChatAvatar(room: room, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room.title)
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    Spacer(minLength: 8)
                    if let date = room.lastActivity {
                        Text(date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if room.unreadCount > 0 {
                        Text("\(room.unreadCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(Color.onAccent)
                            .accessibilityLabel(Text("\(room.unreadCount) unread"))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var excerpt: String {
        let text = room.lastMessageExcerpt ?? ""
        if text.isEmpty { return String(localized: "No messages yet") }
        guard room.hasManyAuthors, let author = room.lastMessageAuthorName, !author.isEmpty else { return text }
        return "\(author): \(text)"
    }
}

enum NewChatMode: String, Identifiable {
    case direct
    case group
    var id: String { rawValue }
}

/// NewChatView picks the people for a direct chat or a group. Mujin users
/// see everyone, grouped by organization; a customer sees colleagues and the
/// Mujin users they already know, which is what the server returns.
struct NewChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var mode: NewChatMode
    let onStarted: (String) -> Void

    init(mode: NewChatMode, onStarted: @escaping (String) -> Void) {
        _mode = State(initialValue: mode)
        self.onStarted = onStarted
    }

    @State private var searchText = ""
    @State private var candidates: [ChatCandidate] = []
    @State private var selected: Set<String> = []
    @State private var groupName = ""
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List { PortalRows {
                Section {
                    Picker("Kind of chat", selection: $mode) {
                        Text("Direct").tag(NewChatMode.direct)
                        Text("Group").tag(NewChatMode.group)
                    }
                    .pickerStyle(.segmented)
                    if mode == .group {
                        TextField("Group name", text: $groupName)
                    }
                }
                if mode == .group {
                    Section {
                        Text("A group needs at least three people, you included.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(groups, id: \.organization) { group in
                    Section(session.isStaff && !group.organization.isEmpty ? group.organization : "") {
                        ForEach(group.people) { person in
                            Button { tap(person) } label: { CandidateRow(person: person, showsOrganization: !session.isStaff, isSelected: mode == .group ? selected.contains(person.userId) : nil) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Color.statusError) }
                }
            } }
.portalList()
            .overlay {
                if candidates.isEmpty { ContentUnavailableView.search(text: searchText) }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people")
            .navigationTitle(mode == .direct ? "New chat" : "New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if mode == .group {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await createGroup() } }
                            .disabled(isWorking || !ChatRules.canCreateGroup(selectedCount: selected.count, name: groupName))
                    }
                }
            }
            .task(id: searchText) {
                if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
                if Task.isCancelled { return }
                do {
                    candidates = try await appModel.connection(for: session.account).chatCandidates(search: searchText.trimmingCharacters(in: .whitespaces))
                } catch {
                    errorText = error.userMessage
                }
            }
        }
        .presentationDetents([.large])
    }

    private var groups: [(organization: String, people: [ChatCandidate])] {
        session.isStaff ? ChatRules.groupedByOrganization(candidates) : [("", candidates.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending })]
    }

    private func tap(_ person: ChatCandidate) {
        if mode == .group {
            if selected.contains(person.userId) { selected.remove(person.userId) } else { selected.insert(person.userId) }
        } else {
            Task { await startDirect(person) }
        }
    }

    private func startDirect(_ person: ChatCandidate) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let id = try await appModel.connection(for: session.account).startDirectChat(userId: person.userId)
            dismiss()
            onStarted(id)
        } catch {
            errorText = error.userMessage
        }
    }

    private func createGroup() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let id = try await appModel.connection(for: session.account).createGroupChat(
                name: groupName.trimmingCharacters(in: .whitespacesAndNewlines), userIds: Array(selected))
            dismiss()
            onStarted(id)
        } catch {
            errorText = error.userMessage
        }
    }
}

/// CandidateRow is a person in a picker: name, organization beside it when it
/// is not already a section, a Staff badge, and a check in a group picker.
struct CandidateRow: View {
    let person: ChatCandidate
    let showsOrganization: Bool
    let isSelected: Bool?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 10) {
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
            let isStaff = person.isMujinUser == true
            if !dynamicTypeSize.isAccessibilitySize { UserAvatar(userId: person.userId, name: person.shownName, size: 32, isStaff: isStaff) }
            VStack(alignment: .leading, spacing: 2) {
                let nameLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
                nameLayout {
                    // With no avatar shown, the mark follows the name.
                    Text(person.shownName).foregroundStyle(.primary).portalNameLine().readsAsStaff(isStaff && !dynamicTypeSize.isAccessibilitySize)
                    if isStaff, dynamicTypeSize.isAccessibilitySize {
                        StaffBadge()
                    }
                }
                if showsOrganization, let organization = person.organizationName, !organization.isEmpty {
                    Text(organization).font(.footnote).foregroundStyle(.secondary).portalNameLine()
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}
