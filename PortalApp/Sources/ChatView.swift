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
    @State private var messageToDelete: ChatMessage?
    @State private var isShowingInfo = DemoOptions.screen == "chat-info"
    @State private var isAddingPeople = DemoOptions.screen == "chat-add-people"
    @State private var drafts = AttachmentDrafts()
    @State private var recorder = VoiceMessageRecorder()
    @State private var isShowingVoiceHint = false
    @State private var isChoosingWhoToCall = DemoOptions.screen == "call-picker"
    @AppStorage("chatVoiceMode") private var isVoiceModePreferred = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var callCenter: CallCenter { appModel.callCenter }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .conversationBar(title: model?.title ?? String(localized: "Chat"), onTitleTap: model?.room == nil ? nil : { isShowingInfo = true })
        .toolbar {
            if let model, canCall(model) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { startCall(model, userIds: nil, isVideoOn: false) } label: { Label("Voice call", systemImage: "phone") }
                        Button { startCall(model, userIds: nil, isVideoOn: true) } label: { Label("Video call", systemImage: "video") }
                        Button { isChoosingWhoToCall = true } label: { Label("Choose who to call", systemImage: "person.2") }
                    } label: { Label("Call", systemImage: "phone") }
                    .accessibilityIdentifier("chatCallMenu")
                }
            }
            if let model, model.room != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // A group's administrators add to it; either person adds to a direct chat, which becomes a group; others see no such row.
                        if model.canAddPeople {
                            Button { isAddingPeople = true } label: { Label("Add people", systemImage: "person.badge.plus") }
                        }
                        Button { isShowingInfo = true } label: { Label("Members", systemImage: "person.2") }
                    } label: { Label("Chat details", systemImage: "ellipsis.circle") }
                }
            }
        }
        .attachmentPickers(drafts)
        .sheet(isPresented: $isAddingPeople) {
            if let model { AddPeopleView(model: model) }
        }
        .sheet(isPresented: $isShowingInfo) {
            if let model { ChatInfoView(model: model) }
        }
        .sheet(isPresented: $isChoosingWhoToCall) {
            if let model {
                CallPeoplePicker(
                    title: "Choose who to call", confirmTitle: "Call", people: (model.room?.currentMembers ?? []).filter { $0.userId != model.currentUserId },
                    showsVideoChoice: true
                ) { userIds, isVideoOn in startCall(model, userIds: userIds, isVideoOn: isVideoOn) }
            }
        }
        .alert(
            "Could not start the call", isPresented: Binding(get: { callCenter.startErrorText != nil }, set: { if !$0 { callCenter.startErrorText = nil } }),
            actions: { Button("OK", role: .cancel) {} }, message: { Text(callCenter.startErrorText ?? "") })
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
            if appModel.isDemo, DemoOptions.screen == "chat-composer" { drafts.stageDemo() }
            if appModel.isDemo, CallDemo.owns(DemoOptions.screen) { CallDemo.markPlayed() }
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
                .safeAreaInset(edge: .top, spacing: 0) { callBanner(model) }
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
                    let messages = model.timeline.messages
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let isNewDay = DayLabel.isNewDay(previous?.date, message.date)
                        if isNewDay, let date = message.date {
                            Text(DayLabel.text(for: date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                        // A deleted message is one quiet line, and a run of them is one.
                        if !(message.isDeleted && previous?.isDeleted == true) {
                        MessageRow(
                            message: message, model: model, isLastOwn: message.id == lastOwnMessageId(model),
                            startsRun: isNewDay || previous == nil || previous?.authorUserId != message.authorUserId || previous?.isAssistant != message.isAssistant,
                            previousMessageId: previous?.id,
                            askDelete: { messageToDelete = $0 }
                        )
                        .id(message.id)
                        }
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
            .scrollDismissesKeyboard(.immediately)
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

    // MARK: calls

    private func canCall(_ model: ChatModel) -> Bool {
        session.capabilities.offersChatCalls && session.isChatCallAvailable && ChatCallRules.canStart(in: model.room, userId: model.currentUserId)
            && session.callBook.goingCall(inChat: model.chatId) == nil && !callCenter.isInCall
    }

    private func startCall(_ model: ChatModel, userIds: [String]?, isVideoOn: Bool) {
        guard let chatId = model.chatId else { return }
        callCenter.begin(
            entry: .start(userIds: userIds), chatId: chatId, chatTitle: model.title, isVideoOn: isVideoOn, account: account, connection: model.connection)
    }

    private func joinCall(_ model: ChatModel, _ call: ChatCall) {
        guard let chatId = model.chatId else { return }
        callCenter.begin(entry: .join(callId: call.id), chatId: chatId, chatTitle: model.title, isVideoOn: false, account: account, connection: model.connection)
    }

    @ViewBuilder
    private func callBanner(_ model: ChatModel) -> some View {
        if session.capabilities.offersChatCalls, let call = session.callBook.goingCall(inChat: model.chatId) {
            CallBanner(
                call: call, isOnThisCall: callCenter.session?.callId == call.id && callCenter.isInCall, onJoin: { joinCall(model, call) },
                onReturn: { callCenter.show() })
        }
    }

    // MARK: voice messages

    private var isVoiceMode: Bool {
        if appModel.isDemo { return DemoOptions.screen == "chat-voice-composer" || DemoOptions.screen == "chat-voice-recording" }
        return isVoiceModePreferred
    }

    private func beginRecording(_ model: ChatModel) async -> VoiceMessageRecorder.StartResult {
        if callCenter.isInCall {
            model.actionError = String(localized: "You cannot record a voice message during a call.")
            return .failed
        }
        let result = await recorder.begin()
        switch result {
        case .denied: model.actionError = String(localized: "Allow the microphone in Settings to record voice messages.")
        case .failed: model.actionError = String(localized: "The recording could not be started.")
        default: model.actionError = nil
        }
        return result
    }

    private func finishRecording(_ model: ChatModel, cancel: Bool) {
        switch recorder.finish(cancel: cancel) {
        case .recording(let recording):
            Task { await model.sendVoice(recording) }
        case .tooShort:
            isShowingVoiceHint = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isShowingVoiceHint = false
            }
        case .cancelled:
            break
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
            TypingBubble()
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
                Label("You were removed from this chat", systemImage: "door.left.hand.open")
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
                if model.editTarget == nil {
                    AttachmentStrip(drafts: drafts)
                        .padding(.horizontal, 16)
                    if let attachError = drafts.errorText {
                        Text(attachError).font(.footnote).foregroundStyle(Color.statusError).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                    }
                }
                if isShowingVoiceHint { VoiceHintView().transition(.opacity) }
                Group {
                if isVoiceMode, canUseVoice(model) {
                    VoiceHoldBar(
                        recorder: recorder, isEnabled: model.canWrite && !model.isSendingVoice, onKeyboard: { isVoiceModePreferred = false },
                        onStart: { await beginRecording(model) }, onFinish: { isCancelled in finishRecording(model, cancel: isCancelled) }
                    )
                    .task {
                        recorder.onLimitReached = { finishRecording(model, cancel: false) }
                        if appModel.isDemo, DemoOptions.screen == "chat-voice-recording" { recorder.stageDemo() }
                    }
                } else {
                ComposerCard(
                    placeholder: fieldPrompt(model), text: $draft, drafts: model.editTarget == nil ? drafts : nil, isEnabled: model.canWrite,
                    canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (model.editTarget == nil && !drafts.items.isEmpty),
                    sendSymbol: model.editTarget == nil ? "arrow.up" : "checkmark", sendLabel: model.editTarget == nil ? "Send" : "Save edit",
                    fieldIdentifier: "chatMessageField", sendIdentifier: "chatSendButton",
                    onEscape: {
                        guard draft.isEmpty, model.replyTarget != nil else { return false }
                        model.replyTarget = nil
                        return true
                    },
                    onSend: {
                        let text = draft
                        draft = ""
                        Task { if await !model.send(text, attachments: drafts) { draft = text } }
                    }
                ) {
                    if canUseVoice(model) {
                        Button { isVoiceModePreferred = true } label: {
                            Image(systemName: "mic.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Record a voice message")
                        .accessibilityIdentifier("voiceModeButton")
                    }
                }
                }
                }
                .onChange(of: draft) { _, text in
                    if !text.isEmpty && model.editTarget == nil { model.noteTyping() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .onChange(of: model.editTarget) { _, target in
            if let target { draft = target.text }
        }
    }

    /// Voice messages are for a chat the person can write in, when the server has them and nothing else is being written.
    private func canUseVoice(_ model: ChatModel) -> Bool {
        (session.capabilities.offersVoiceMessages || (appModel.isDemo && DemoOptions.screen?.hasPrefix("chat-voice") == true)) && model.canWrite
            && model.editTarget == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drafts.items.isEmpty
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
                        HStack(spacing: 10) {
                            UserAvatar(userId: candidate.kind == .user ? candidate.id : nil, name: candidate.name, size: 32, isAssistant: candidate.kind == .agent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.name).foregroundStyle(.primary)
                                Text(candidate.detail ?? (candidate.kind == .agent ? String(localized: "Assistant") : String(localized: "Person")))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if candidate.id != suggestions.last?.id { Divider().padding(.leading, 54) }
                }
            }
            .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
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

/// BubbleKey is everything a chat bubble draws, so the bubble is drawn again only when one of them changes.
private struct BubbleKey: Equatable {
    let message: ChatMessage
    let reactions: [Reaction]
    let isMine: Bool
    let mentionNames: [String]
    let memberNames: [String]
    let canWrite: Bool
    let canEdit: Bool
    let canDelete: Bool
    let hasPreviews: Bool
}

/// MessageRow is one message: the author, a quote when it replies, the words
/// or a note that it was deleted, reactions, link cards, and who has read it.
private struct MessageRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SessionModel.self) private var session
    @Environment(AppModel.self) private var appModel
    let message: ChatMessage
    let model: ChatModel
    let isLastOwn: Bool
    let startsRun: Bool
    /// The message directly above this one, which a reply to it need not quote.
    var previousMessageId: String?
    let askDelete: (ChatMessage) -> Void

    private var isMine: Bool { message.authorUserId == model.currentUserId && !message.isAssistant }

    var body: some View {
        if message.isDeleted {
            Text("This message was deleted")
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else {
        HStack(alignment: .top, spacing: 8) {
            // Others have a small round picture at the start of each run of their messages.
            if !isMine {
                if startsRun {
                    UserAvatar(userId: message.authorUserId, name: message.authorName ?? model.member(message.authorUserId)?.shownName ?? "", size: 28, isAssistant: message.isAssistant)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine, startsRun { authorLine }
                if showsQuote { quote }
                bubble
                ForEach(model.previews[message.id] ?? []) { card in
                    LinkPreviewCardView(card: card, connection: model.connection)
                        .frame(maxWidth: 320)
                }
                if isMine, isLastOwn { receipt }
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        }
    }

    private var authorLine: some View {
        let member = model.member(message.authorUserId)
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Text(message.isAssistant ? ((message.authorName ?? "").isEmpty ? String(localized: "Assistant") : message.authorName!) : (message.authorName ?? member?.shownName ?? String(localized: "Someone")))
                .font(.caption.weight(.semibold))
                .portalNameLine()
            if message.isAssistant, let name = message.onBehalfOfUserName, !name.isEmpty {
                Text("for \(name)").font(.caption).foregroundStyle(.secondary).portalNameLine()
            }
            // The organization is shown beside a person from another one.
            if !message.isAssistant, let organization = message.authorOrganizationName ?? member?.organizationName, !organization.isEmpty,
                member?.organizationId != nil, member?.organizationId != model.member(model.currentUserId)?.organizationId
            {
                Text(organization).font(.caption).foregroundStyle(.secondary).portalNameLine()
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

    /// A quote of the message right above, or of one the reader can see in the transcript, adds nothing.
    private var showsQuote: Bool {
        guard message.isReply, let replyId = message.replyToMessageId else { return false }
        if replyId == previousMessageId { return false }
        if !message.hasQuotedText, model.timeline.messages.contains(where: { $0.id == replyId }) { return false }
        return true
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
            StableBubble(key: BubbleKey(
                message: message, reactions: model.timeline.reactions(for: message.id), isMine: isMine,
                mentionNames: model.mentionNames, memberNames: (model.room?.members ?? []).map(\.shownName), canWrite: model.canWrite,
                canEdit: model.canEdit(message), canDelete: model.canDelete(message), hasPreviews: !(model.previews[message.id] ?? []).isEmpty)
            ) {
            HoldableMessage(actions: heldActions) {
            if let voice = message.voice {
                VoiceMessageBubble(
                    messageId: message.id, voice: voice, isMine: isMine, connection: model.connection, isDemo: appModel.isDemo,
                    isShowingTextAtStart: DemoOptions.screen == "chat-voice" && message.id == "v3")
            } else if let call = message.call {
                CallLineView(call: call, currentUserId: model.currentUserId)
            } else {
            VStack(alignment: .leading, spacing: 2) {
                // People write plain text; a table or a Markdown link in it is laid out as Markdown, which gives up the name chips.
                if message.isAssistant || MarkdownBlocks.hasTable(message.text) || message.text.contains("](") {
                    RichBodyView(markdown: message.text, connection: model.connection, isSelectable: false)
                } else if TicketBody.hasAttachments(message.text) {
                    RichBodyView(markdown: message.text, connection: model.connection) { words in
                        Text(Self.attributed(MentionText.rendered(words, members: model.room?.members ?? [], agents: model.agents), mentionNames: model.mentionNames, onAccent: isMine))
                    }
                } else {
                    Text(Self.attributed(MentionText.rendered(message.text, members: model.room?.members ?? [], agents: model.agents), mentionNames: model.mentionNames, onAccent: isMine))
                }
                if message.isEdited {
                    Text("edited").font(.caption2).foregroundStyle(AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isMine ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .foregroundStyle(.primary)
            }
            }
            // The reactions sit on the bubble's corner; a tap toggles the person's own.
            .reactionCorner(model.timeline.reactions(for: message.id), currentUserId: model.currentUserId, isLeading: isMine) { emoji in
                Task { await model.react(messageId: message.id, emoji: emoji) }
            }
            }
            .equatable()
        }
    }

    /// Links in a message are live; the text is otherwise shown as written.
    static func attributed(_ text: String, mentionNames: [String], onAccent: Bool) -> AttributedString {
        // The names of agents and people in the message read as chips.
        var result = BareLinks.linked(plainText: text)
        for span in Mentions.spans(in: text, names: mentionNames) {
            guard let start = AttributedString.Index(span.lowerBound, within: result), let end = AttributedString.Index(span.upperBound, within: result) else { continue }
            result[start..<end].font = .body.weight(.semibold)
            result[start..<end].backgroundColor = onAccent ? Color.onAccent.opacity(0.25) : Color.accentColor.opacity(0.18)
        }
        // A link reads as in an answer.
        return MarkdownView.styledLinks(result)
    }

    /// What a long press on the message offers. A person reacts to anyone's message; the rest follows what the room allows.
    private var heldActions: MessageActions {
        let hasPreviews = !(model.previews[message.id] ?? []).isEmpty
        return MessageActions(
            messageId: message.id, text: message.text, isTrailing: isMine,
            ownReaction: Reactions.summaries(model.timeline.reactions(for: message.id), currentUserId: model.currentUserId).first { $0.isMine }?.emoji,
            onReact: { emoji in Task { await model.react(messageId: message.id, emoji: emoji) } },
            onReply: model.canWrite ? { model.replyTarget = message } : nil,
            onEdit: model.canEdit(message) ? { model.editTarget = message } : nil,
            onRemoveLinkPreviews: isMine && hasPreviews ? { Task { await model.removePreviews(of: message) } } : nil,
            onDelete: model.canDelete(message) ? { askDelete(message) } : nil)
    }

    @ViewBuilder
    private var receipt: some View {
        let count = model.timeline.readerCount(of: message.id, excluding: model.currentUserId)
        if count > 0 {
            HStack(spacing: 4) {
                if model.room?.isGroup != true { UserAvatar(userId: model.room?.avatarMembers(excluding: model.currentUserId).first?.userId, name: model.title, size: 16) }
                if model.room?.isGroup == true {
                    Text("Seen by \(count)")
                } else {
                    Text("Seen")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
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
                                .swipeActions {
                                    if model.isAdmin, room.isGroup, member.userId != model.currentUserId {
                                        Button("Remove", role: .destructive) { memberToRemove = member }
                                    }
                                }
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
                        if model.canAddPeople {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 10) {
        if !dynamicTypeSize.isAccessibilitySize { UserAvatar(userId: member.userId, name: member.shownName, size: 32) }
        VStack(alignment: .leading, spacing: 2) {
            let nameLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
            nameLayout {
                Text(isViewer ? String(localized: "You") : member.shownName).portalNameLine()
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
                Text(organization).font(.footnote).foregroundStyle(.secondary).portalNameLine()
            }
        }
        }
    }
}

/// AddPeopleView picks people to add to a chat. They join that same chat and read its whole history; a direct chat becomes a group.
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
                Section {
                    ForEach(shown) { person in
                        Button {
                            if selected.contains(person.userId) { selected.remove(person.userId) } else { selected.insert(person.userId) }
                        } label: {
                            CandidateRow(person: person, showsOrganization: true, isSelected: selected.contains(person.userId))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(model.room?.isGroup == false
                        ? LocalizedStringKey("This chat becomes a group with them in it. They can read everything said in it so far.")
                        : LocalizedStringKey("They join this group and can read everything said in it so far."))
                        .textCase(nil)
                }
            } }
            .portalList()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search people")
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
