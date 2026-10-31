import PortalKit
import SwiftUI
import UIKit

/// ChatView is one chat with people: their messages on the left, the
/// person's own on the right, replies, edits, reactions, who is typing, who
/// has read, and cards under messages that hold links. The assistant joins
/// when a message mentions the agent by its name or replies to one of its answers.
struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account
    let conversationId: String
    let chatId: String?

    @State private var model: ChatModel?
    @State private var draft = DemoOptions.screen == "chat-mention" ? "Can @" : ""
    @State private var emojiTarget: ConversationView.EmojiTarget?
    @State private var messageToDelete: ChatMessage?
    @State private var isShowingInfo = DemoOptions.screen == "chat-info"
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.title ?? String(localized: "Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let model, model.room != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingInfo = true } label: { Label("Chat details", systemImage: "info.circle") }
                }
            }
        }
        .sheet(isPresented: $isShowingInfo) {
            if let model { ChatInfoView(model: model) }
        }
        .sheet(item: $emojiTarget) { target in
            EmojiEntryView { emoji in Task { await model?.react(messageId: target.id, emoji: emoji) } }
        }
        .confirmationDialog(
            "Delete this message?", isPresented: Binding(get: { messageToDelete != nil }, set: { if !$0 { messageToDelete = nil } }),
            titleVisibility: .visible, presenting: messageToDelete
        ) { message in
            Button("Delete message", role: .destructive) { Task { await model?.delete(message) } }
        } message: { _ in
            Text("Everyone in the chat will see that it was deleted.")
        }
        .task(id: conversationId) {
            let chatModel = ChatModel(
                conversationId: conversationId, chatId: chatId, currentUserId: account.userId, connection: appModel.connection(for: account),
                socketFactory: appModel.socketFactory, onError: { [appModel, account] error in appModel.handle(error, account: account) })
            chatModel.offersStructuredMentions = session.capabilities.offersStructuredMentions
            model = chatModel
            chatModel.start()
            if appModel.isDemo, DemoOptions.screen == "chat-reply" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                chatModel.replyTarget = chatModel.timeline.messages.first { $0.authorUserId == "user02" }
            }
        }
        .onAppear { model?.start() }
        .onDisappear { model?.stop() }
    }

    @ViewBuilder
    private func content(_ model: ChatModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load this chat", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.reload() } }
            }
        case .loaded:
            messages(model)
                .safeAreaInset(edge: .bottom, spacing: 0) { composer(model) }
        }
    }

    private func messages(_ model: ChatModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.window.earlierCount > 0 {
                        Button { Task { await model.loadEarlier() } } label: {
                            Text("\(model.window.earlierCount) earlier messages").font(.footnote).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoadingEarlier)
                    }
                    if model.timeline.messages.isEmpty {
                        ContentUnavailableView {
                            Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            if let agent = model.agents.first?.name {
                                Text("Say hello. Type @ to bring in \(agent).")
                            } else {
                                Text("Say hello. Type @ to mention someone.")
                            }
                        }
                        .padding(.top, 48)
                    }
                    ForEach(model.timeline.messages) { message in
                        MessageRow(
                            message: message, model: model, isLastOwn: message.id == lastOwnMessageId(model),
                            moreEmoji: { emojiTarget = ConversationView.EmojiTarget(id: $0) }, askDelete: { messageToDelete = $0 }
                        )
                        .id(message.id)
                    }
                    ForEach(model.questions) { card in
                        QuestionCardView(card: card, onAnswer: { answer in Task { await model.answer(card, with: answer) } }, onChatInstead: nil)
                    }
                    ForEach(model.approvals) { card in
                        ApprovalCardView(card: card) { isApproved in Task { await model.decide(card, isApproved: isApproved) } }
                    }
                    if model.isOwnTurnRunning && model.questions.isEmpty && model.approvals.isEmpty {
                        Label("The assistant is working on your message", systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    typingLine(model)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: ConversationView.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.portalPage)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.timeline.messages.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .top) {
                if !model.isFeedLive {
                    Label("Reconnecting", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect()
                        .padding(.top, 8)
                }
            }
        }
    }

    private func lastOwnMessageId(_ model: ChatModel) -> String? {
        model.timeline.messages.last { $0.authorUserId == model.currentUserId && !$0.isDeleted }?.id
    }

    @ViewBuilder
    private func typingLine(_ model: ChatModel) -> some View {
        let people = model.peopleTyping
        if !people.isEmpty {
            Label(
                people.count == 1 ? LocalizedStringKey("\(people[0]) is typing") : LocalizedStringKey("\(people.joined(separator: ", ")) are typing"),
                systemImage: "ellipsis.bubble")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if model.isAssistantAnswering {
            Label("The assistant is answering", systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func composer(_ model: ChatModel) -> some View {
        VStack(spacing: 6) {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(Color.statusError).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            }
            if !model.canWrite {
                Label("You left this chat. You can read what was said while you were in it.", systemImage: "door.left.hand.open")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                if let reply = model.replyTarget {
                    ReferencesBar(
                        reply: ReplyReference(
                            messageId: reply.id, authorName: reply.authorName ?? String(localized: "Assistant"), excerpt: reply.text,
                            isOwn: reply.authorUserId == model.currentUserId && !reply.isAssistant),
                        onCancelReply: { model.replyTarget = nil }
                    ) {}
                    .padding(.horizontal, 12)
                }
                mentionList(model)
                if let editing = model.editTarget {
                    banner(icon: "pencil", title: String(localized: "Editing your message"), detail: editing.text) {
                        model.editTarget = nil
                        draft = ""
                    }
                }
                if let agent = model.addressedAgent(in: draft) {
                    Label("\(agent.name ?? String(localized: "The assistant")) will answer", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }
                GlassEffectContainer {
                    // Large text puts the button under the field so the prompt can wrap.
                    let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8)) : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
                    layout {
                        TextField(fieldPrompt(model), text: $draft, axis: .vertical)
                            .lineLimit(1...6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .accessibilityIdentifier("chatMessageField")
                            // With a hardware keyboard, Escape in an empty field takes the reply away.
                            .onKeyPress(.escape, phases: .down) { _ in
                                guard draft.isEmpty, model.replyTarget != nil else { return .ignored }
                                model.replyTarget = nil
                                return .handled
                            }
                            .onChange(of: draft) { _, text in
                                if !text.isEmpty && model.editTarget == nil { model.noteTyping() }
                            }
                        Button {
                            let text = draft
                            draft = ""
                            Task { if await !model.send(text) { draft = text } }
                        } label: {
                            Image(systemName: model.editTarget == nil ? "arrow.up" : "checkmark").frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .frame(minWidth: 44, minHeight: 44)
                        .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(model.editTarget == nil ? Text("Send") : Text("Save edit"))
                        .accessibilityIdentifier("chatSendButton")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: ConversationView.readableWidth + 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .onChange(of: model.editTarget) { _, target in
            if let target { draft = target.text }
        }
    }

    private func fieldPrompt(_ model: ChatModel) -> LocalizedStringKey {
        if !dynamicTypeSize.isAccessibilitySize, let agent = model.agents.first?.name { return LocalizedStringKey("Message, or @\(agent) to ask") }
        return LocalizedStringKey("Message")
    }

    /// The list that opens above the composer when the draft ends with an @:
    /// agents first, then the people in the chat.
    @ViewBuilder
    private func mentionList(_ model: ChatModel) -> some View {
        let suggestions = model.mentionSuggestions(for: draft)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { candidate in
                    Button {
                        draft = Mentions.inserting(candidate, into: draft)
                        model.pick(candidate)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: candidate.kind == .agent ? "sparkles" : "person")
                                .foregroundStyle(Color.portalSecondary)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(candidate.name).foregroundStyle(.primary)
                            if let detail = candidate.detail, !detail.isEmpty {
                                Text(detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if candidate.id != suggestions.last?.id { Divider() }
                }
            }
            .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
            .padding(.horizontal, 12)
            .frame(maxWidth: ConversationView.readableWidth + 32)
        }
    }

    private func banner(icon: String, title: String, detail: String, onClose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 20)
    }
}

/// MessageRow is one message: the author, a quote when it replies, the words
/// or a note that it was deleted, reactions, link cards, and who has read it.
private struct MessageRow: View {
    @Environment(SessionModel.self) private var session
    let message: ChatMessage
    let model: ChatModel
    let isLastOwn: Bool
    let moreEmoji: (String) -> Void
    let askDelete: (ChatMessage) -> Void

    private var isMine: Bool { message.authorUserId == model.currentUserId && !message.isAssistant }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if !isMine { authorLine }
            if message.isReply { quote }
            bubble
            ReactionStrip(reactions: model.timeline.reactions(for: message.id), currentUserId: model.currentUserId) { emoji in
                Task { await model.react(messageId: message.id, emoji: emoji) }
            }
            ForEach(model.previews[message.id] ?? []) { card in
                LinkPreviewCardView(card: card, connection: model.connection)
                    .frame(maxWidth: 320)
            }
            if isMine, isLastOwn { receipt }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private var authorLine: some View {
        let member = model.member(message.authorUserId)
        return HStack(spacing: 6) {
            Text(message.isAssistant ? ((message.authorName ?? "").isEmpty ? String(localized: "Assistant") : message.authorName!) : (message.authorName ?? member?.shownName ?? String(localized: "Someone")))
                .font(.caption.weight(.semibold))
            if message.isAssistant, let name = message.onBehalfOfUserName, !name.isEmpty {
                Text("for \(name)").font(.caption).foregroundStyle(.secondary)
            }
            // The organization is shown beside a person from another one.
            if !message.isAssistant, let organization = message.authorOrganizationName ?? member?.organizationName, !organization.isEmpty,
                member?.organizationId != nil, member?.organizationId != model.member(model.currentUserId)?.organizationId
            {
                Text(organization).font(.caption).foregroundStyle(.secondary)
            }
            if member?.isMujinUser == true {
                Text("Staff")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quote: some View {
        Group {
            if message.hasQuotedText {
                SentQuote(authorName: message.replyToAuthorName ?? "", excerpt: message.replyToExcerpt ?? "")
            } else {
                Text("A message from before you joined").font(.caption).italic().foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        if message.isDeleted {
            Text("This message was deleted")
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if message.isAssistant {
                    MarkdownView(markdown: message.text)
                } else {
                    Text(Self.attributed(message.text, mentionNames: model.mentionNames, onAccent: isMine))
                        .textSelection(.enabled)
                }
                if message.isEdited {
                    Text("edited").font(.caption2).foregroundStyle(isMine ? AnyShapeStyle(Color.onAccent.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isMine ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.portalCard),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .foregroundStyle(isMine ? AnyShapeStyle(Color.onAccent) : AnyShapeStyle(.primary))
            .contextMenu { menu }
            .accessibilityAction(named: Text("Reply")) { model.replyTarget = message }
        }
    }

    /// Links in a message are live; the text is otherwise shown as written.
    static func attributed(_ text: String, mentionNames: [String], onAccent: Bool) -> AttributedString {
        // The names of agents and people in the message read as chips.
        var result = AttributedString(text)
        for span in Mentions.spans(in: text, names: mentionNames) {
            guard let start = AttributedString.Index(span.lowerBound, within: result), let end = AttributedString.Index(span.upperBound, within: result) else { continue }
            result[start..<end].font = .body.weight(.semibold)
            result[start..<end].backgroundColor = onAccent ? Color.onAccent.opacity(0.25) : Color.accentColor.opacity(0.18)
        }
        return result
    }

    @ViewBuilder
    private var menu: some View {
        if model.canWrite {
            Button { model.replyTarget = message } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        }
        ForEach(Reactions.palette, id: \.self) { emoji in
            Button(emoji) { Task { await model.react(messageId: message.id, emoji: emoji) } }
        }
        Button { moreEmoji(message.id) } label: { Label("More emoji", systemImage: "face.smiling") }
        Button { UIPasteboard.general.string = message.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        if model.canEdit(message) {
            Button { model.editTarget = message } label: { Label("Edit", systemImage: "pencil") }
        }
        if isMine, !(model.previews[message.id] ?? []).isEmpty {
            Button { Task { await model.removePreviews(of: message) } } label: { Label("Remove link previews", systemImage: "link.badge.plus") }
        }
        if model.canDelete(message) {
            Button(role: .destructive) { askDelete(message) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var receipt: some View {
        let count = model.timeline.readerCount(of: message.id, excluding: model.currentUserId)
        if count > 0 {
            if model.room?.isGroup == true {
                Label("Seen by \(count)", systemImage: "checkmark").font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("Seen", systemImage: "checkmark").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// ChatInfoView is a chat's members and settings.
struct ChatInfoView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel

    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var isAddingPeople = false
    @State private var isConfirmingLeave = false
    @State private var memberToRemove: ChatMember?

    var body: some View {
        NavigationStack {
            List { PortalRows {
                if let room = model.room {
                    Section("People") {
                        ForEach(room.currentMembers) { member in
                            MemberRow(member: member, isViewer: member.userId == model.currentUserId, viewerOrganizationId: model.member(model.currentUserId)?.organizationId)
                                .contextMenu {
                                    if model.isAdmin, room.isGroup, member.userId != model.currentUserId {
                                        Button {
                                            Task { await model.apply { try await model.connection.setChatMemberAdmin(chatId: room.id, userId: member.userId, isAdmin: member.isAdmin != true) } }
                                        } label: {
                                            member.isAdmin == true
                                                ? Label("Remove as admin", systemImage: "person.badge.minus")
                                                : Label("Make admin", systemImage: "person.badge.shield.checkmark")
                                        }
                                        Button(role: .destructive) { memberToRemove = member } label: { Label("Remove from chat", systemImage: "person.fill.xmark") }
                                    }
                                }
                        }
                        if model.isAdmin, room.isGroup, room.canWrite {
                            Button { isAddingPeople = true } label: { Label("Add people", systemImage: "person.badge.plus") }
                        }
                    }
                    Section {
                        Picker("Notify me", selection: Binding(
                            get: { room.readerNotificationLevel ?? "all" },
                            set: { level in Task { await model.apply { try await model.connection.setChatNotificationLevel(chatId: room.id, level: level) } } })
                        ) {
                            Text("Every message").tag("all")
                            Text("Mentions only").tag("mentions")
                            Text("Nothing").tag("none")
                        }
                        if room.isGroup, model.isAdmin {
                            Toggle("Save what is said to memory", isOn: Binding(
                                get: { room.isMemoryFilingEnabled == true },
                                set: { value in Task { await model.apply { try await model.connection.setChatMemoryFiling(chatId: room.id, isEnabled: value) } } }))
                        }
                    } footer: {
                        if room.isGroup, model.isAdmin {
                            Text("Memory is filed under the organization's, never under a person's own.")
                        }
                    }
                    if room.isGroup, model.isAdmin {
                        Section {
                            Button { renameDraft = room.title; isRenaming = true } label: { Label("Rename group", systemImage: "pencil") }
                        }
                    }
                    if room.isGroup, room.canWrite {
                        Section {
                            Button(role: .destructive) { isConfirmingLeave = true } label: {
                                Label("Leave chat", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Color.statusError)
                            }
                        }
                    }
                    if let error = model.actionError {
                        Section { Text(error).foregroundStyle(Color.statusError) }
                    }
                }
            } }
.portalList()
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Rename group", isPresented: $isRenaming) {
                TextField("Name", text: $renameDraft)
                Button("Save") {
                    guard let room = model.room else { return }
                    let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { Task { await model.apply { try await model.connection.renameChat(chatId: room.id, name: name) } } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Leave this chat?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                Button("Leave chat", role: .destructive) {
                    guard let room = model.room else { return }
                    Task {
                        await model.apply { try await model.connection.removeChatMember(chatId: room.id) }
                        dismiss()
                    }
                }
            } message: {
                Text("You can still read what was said while you were in it.")
            }
            .confirmationDialog(
                "Remove this person?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
                titleVisibility: .visible, presenting: memberToRemove
            ) { member in
                Button("Remove \(member.shownName)", role: .destructive) {
                    guard let room = model.room else { return }
                    Task { await model.apply { try await model.connection.removeChatMember(chatId: room.id, userId: member.userId) } }
                }
            }
            .sheet(isPresented: $isAddingPeople) {
                AddPeopleView(model: model)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MemberRow: View {
    let member: ChatMember
    let isViewer: Bool
    let viewerOrganizationId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(isViewer ? String(localized: "You") : member.shownName)
                if member.isMujinUser == true {
                    Text("Staff")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if member.isAdmin == true {
                    Text("Admin").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !isViewer, member.organizationId != viewerOrganizationId, let organization = member.organizationName, !organization.isEmpty {
                Text(organization).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// AddPeopleView picks people to add to a group.
private struct AddPeopleView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let model: ChatModel

    @State private var searchText = ""
    @State private var candidates: [ChatCandidate] = []
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List { PortalRows {
                ForEach(shown) { person in
                    Button {
                        if selected.contains(person.userId) { selected.remove(person.userId) } else { selected.insert(person.userId) }
                    } label: {
                        CandidateRow(person: person, showsOrganization: true, isSelected: selected.contains(person.userId))
                    }
                    .buttonStyle(.plain)
                }
            } }
.portalList()
            .searchable(text: $searchText, prompt: "Search people")
            .navigationTitle("Add people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let room = model.room else { return }
                        let ids = Array(selected)
                        Task {
                            await model.apply { try await model.connection.addChatMembers(chatId: room.id, userIds: ids) }
                            dismiss()
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task(id: searchText) {
                if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
                if Task.isCancelled { return }
                candidates = (try? await model.connection.chatCandidates(search: searchText.trimmingCharacters(in: .whitespaces))) ?? []
            }
        }
    }

    private var shown: [ChatCandidate] {
        let present = Set((model.room?.currentMembers ?? []).map(\.userId))
        return candidates.filter { !present.contains($0.userId) }
    }
}
