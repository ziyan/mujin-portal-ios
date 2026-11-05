import PortalKit
import SwiftUI

/// ConversationListView is the Assistant tab: what waits for the person,
/// then their conversations, newest first, with search and a way to start one.
struct ConversationListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var model: ConversationListModel?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection = SplitSelection()
    /// Conversations opened as chats with people, which a notification can do before the list has their row.
    @State private var chatConversationIds: Set<String> = []
    @State private var searchText = ""
    @State private var isComposing = false

    var body: some View {
        NavigationSplitView {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Chat")
            .notificationsBell()
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isComposing = true
                    } label: {
                        Label("New conversation", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("newConversationButton")
                }
            }
        } detail: {
            if let shownConversationId = selection.detailId(isCompact: horizontalSizeClass == .compact) {
                NavigationStack {
                    // A chat with people and a conversation with the assistant are opened the same way. Each draws its own
                    // messages, so the choice is made once: a screen that changed when the list arrived would draw them twice.
                    let listed = model?.conversation(id: shownConversationId)
                    if listed?.conversationKind == "chat" || chatConversationIds.contains(shownConversationId) {
                        ChatView(account: account, conversationId: shownConversationId, chatId: listed?.chatId)
                    } else if listed == nil, model?.phase ?? .loading == .loading {
                        ProgressView()
                    } else {
                        ConversationView(
                            account: account, conversationId: shownConversationId,
                            title: model?.conversation(id: shownConversationId)?.title,
                            onTitleChanged: { [shownConversationId] title in model?.retitle(id: shownConversationId, title: title) })
                    }
                }
                .id(shownConversationId)
            } else {
                ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .task(id: account.accountKey) {
            // Kept across visits: the list is not rebuilt, and does not flash, when the tab comes back.
            let listModel = model ?? ConversationListModel(
                account: account, connection: appModel.connection(for: account),
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            listModel.offersChats = session.capabilities.offersChats
            listModel.cache = session.cache
            model = listModel
            await listModel.load()
            if appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("conversation:") {
                selection.selectedId = String(screen.dropFirst("conversation:".count))
            }
            if appModel.isDemo, DemoOptions.screen == "list-started" {
                // A conversation just started: listed at once, at the top, though the demo server does not list it yet.
                await listModel.didStartAssistantConversation(id: "conversation-started", text: "Which dock doors were slow this week and why?")
            }
            if appModel.isDemo, let screen = DemoOptions.screen {
                if screen.hasPrefix("chat:") { selection.selectedId = String(screen.dropFirst("chat:".count)) }
                if screen == "chat-info" { selection.selectedId = "chatconv02" }
                if screen == "photo-chat" { selection.selectedId = "conversation-photos" }
                if screen == "voice" || screen == "conversation-links" || screen == "message-actions" || screen == "select-text" || screen == "title-event" { selection.selectedId = "conversation01" }
                if screen == "side-chat-links" { selection.selectedId = "conversation05" }
                if screen == "chat-reply" || screen == "chat-composer" || screen == "chat-mention" || screen == "chat-add-people" || screen == "chat-link-tap" || screen == "chat-links" || screen == "chat-message-actions" { selection.selectedId = "chatconv01" }
                if let conversationId = CallDemo.conversationId(for: screen) { selection.selectedId = conversationId }
                if screen.hasPrefix("chats-new") { isComposing = true }
            }
        }
        .task(id: searchText) {
            // Search waits for a pause in typing.
            if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
            if Task.isCancelled { return }
            await model?.search(searchText)
        }
        .onChange(of: selection.selectedId) { _, id in model?.openConversationId = id }
        .sheet(isPresented: Binding(get: { isComposing || session.composeRequest != nil }, set: { if !$0 { isComposing = false; session.composeRequest = nil } })) {
            ComposeMessageView(request: session.composeRequest, onSent: { selection.selectedId = $0 }, onStarted: { conversationId, text, isChat in
                // The row is there at once; the server is asked afterwards, and the title comes when it is set.
                Task {
                    if isChat {
                        await model?.didStartChat(id: conversationId)
                    } else {
                        await model?.didStartAssistantConversation(id: conversationId, text: text)
                    }
                }
            })
        }
        .onChange(of: session.chatToOpen, initial: true) { _, conversationId in
            guard let conversationId else { return }
            chatConversationIds.insert(conversationId)
            selection.selectedId = conversationId
            session.chatToOpen = nil
            Task { await model?.load() }
        }
        .onChange(of: session.conversationToOpen, initial: true) { _, conversationId in
            guard let conversationId else { return }
            selection.selectedId = conversationId
            session.conversationToOpen = nil
            Task { await model?.load() }
        }
    }

    @ViewBuilder
    private func content(_ model: ConversationListModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load conversations", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            if model.conversations.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No conversations yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start one to ask your assistant something.")
                    } actions: {
                        Button("New conversation") { isComposing = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else {
                List(selection: $selection.selectedId) {
                    PortalRows {
                    Section {
                        ForEach(ConversationOrdering.ordered(model.conversations, waitingIds: Set(model.conversations.map(\.id).filter { (session.waitingCounts[$0] ?? 0) > 0 }))) { conversation in
                            NavigationLink(value: conversation.id) {
                                ConversationRow(conversation: conversation, waitingCount: session.waitingCounts[conversation.id] ?? 0)
                            }
                            // The row is plainly tappable: no chevron takes width from the title.
                            .navigationLinkIndicatorVisibility(.hidden)
                            .swipeActions {
                                if conversation.isMain != true {
                                    Button("Archive", role: .destructive) { Task { await model.archive(conversation) } }
                                }
                            }
                        }
                    }
                    }
}
.portalRootList()
                .refreshable {
                    await model.load(force: true)
                    await session.refreshWaiting()
                }
            }
        }
    }
}

/// WaitingRow is a question or an approval that waits, answerable in place.
private struct WaitingRow: View {
    @Environment(SessionModel.self) private var session
    let item: WaitingItem
    let onOpen: () -> Void

    @State private var answer = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        item.isApproval ? LocalizedStringKey("Approval needed") : LocalizedStringKey("Question"),
                        systemImage: item.isApproval ? "checkmark.shield" : "questionmark.bubble"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(item.isApproval ? AnyShapeStyle(Color.statusWarning) : AnyShapeStyle(.secondary))
                    Text(item.promptText ?? item.toolName ?? "")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                    if let title = item.conversationTitle, !title.isEmpty {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if item.isApproval {
                HStack(spacing: 12) {
                    Button {
                        Task { errorText = await session.decide(item, isApproved: false) }
                    } label: {
                        Text("Reject").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        Task { errorText = await session.decide(item, isApproved: true) }
                    } label: {
                        Text("Approve").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            } else {
                HStack {
                    TextField("Your answer", text: $answer)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit(submit)
                    Button("Send", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Color.statusError)
            }
        }
        .padding(.vertical, 4)
    }

    private func submit() {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            errorText = await session.answer(item, with: text)
            if errorText == nil { answer = "" }
        }
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary
    let waitingCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The title takes the width: the time is small at the top right of its line, and the one signal
        // (Needs you, an unread dot or a spinner) sits at the right of the preview line.
        let isLarge = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            if let room = conversation.chat, conversation.conversationKind == "chat" {
                ChatAvatar(room: room, size: 44)
            } else {
                PersonAvatar(name: conversation.chat?.title ?? "", size: 44, isAssistant: conversation.conversationKind != "chat")
            }
            VStack(alignment: .leading, spacing: 3) {
                let titleLine = AnyLayout(isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8)))
                titleLine {
                    Text(rowTitle)
                        .font(.headline)
                        .lineLimit(isLarge ? 3 : 1)
                    if !isLarge { Spacer(minLength: 4) }
                    if case let date = ConversationOrdering.activity(conversation), date > .distantPast {
                        Text(date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                // At the large sizes the signal goes on its own line under the preview, which may wrap to two lines.
                let previewLine = AnyLayout(isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8)))
                previewLine {
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(isLarge ? 2 : 1)
                    }
                    if !isLarge { Spacer(minLength: 4) }
                    signal
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// One signal per row: it needs the person, or there is something unread, or it is working.
    @ViewBuilder
    private var signal: some View {
        if waitingCount > 0 {
            Text("Needs you")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.statusWarning.opacity(0.18), in: Capsule())
                .foregroundStyle(Color.statusWarning)
                .fixedSize()
        } else if (conversation.chat?.unreadCount ?? 0) > 0 {
            Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                .accessibilityLabel(Text("\(conversation.chat?.unreadCount ?? 0) unread"))
        } else if conversation.isRunning || conversation.hasRunningBackgroundWork == true {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Working")
        }
    }

    private var rowTitle: String {
        if conversation.isMain == true { return String(localized: "Main chat") }
        if conversation.conversationKind == "chat" { return conversation.chat?.title ?? String(localized: "Chat") }
        return conversation.title?.isEmpty == false ? conversation.title! : String(localized: "New conversation")
    }

    /// One line of the last message: in a group the author first, a mention token read as a name.
    private var preview: String {
        if let room = conversation.chat, conversation.conversationKind == "chat" {
            let text = MentionText.rendered(room.lastMessageExcerpt ?? "", members: room.members ?? [])
            guard room.isGroup, let author = room.lastMessageAuthorName, !author.isEmpty, !text.isEmpty else { return text }
            return "\(author.split(separator: " ").first.map(String.init) ?? author): \(text)"
        }
        return conversation.lastMessageExcerpt ?? conversation.summary ?? ""
    }
}
