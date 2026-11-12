import PortalKit
import SwiftUI
import UIKit

/// ChatView is one chat with people: their messages on the left, the
/// person's own on the right, replies, edits, reactions, who is typing, who
/// has read, and cards under messages that hold links. The assistant joins
/// when a message mentions the agent by its name or replies to one of its answers. On a server with message threads a reply goes in
/// a thread: the main history shows how many replies a message has, and a tap opens the thread as a screen of its own, which is
/// this same view with a `threadRootMessageId`.
struct ChatView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account
    let conversationId: String
    let chatId: String?
    /// The message whose thread this screen shows alone, with its own composer. Nil for the whole chat.
    var threadRootMessageId: String?
    /// A thread a notification asks this chat to open on, which this view takes and clears.
    var requestedThreadRootMessageId: Binding<String?> = .constant(nil)

    @State private var model: ChatModel?
    @State private var openedThreadRootId: String?
    /// The threads the person waved away from the hint that offers to continue one, while this screen is open.
    /// The message a link pointed at, marked for a moment.
    @State private var highlightedMessageId: String?
    @State private var isOnScreen = false
    @State private var draft = DemoOptions.screen == "chat-mention" ? "Can @" : ""
    @State private var messageToDelete: ChatMessage?
    @State private var isShowingInfo = DemoOptions.screen == "chat-info" || DemoOptions.screen == "chat-site-info" || DemoOptions.screen?.hasPrefix("chat-call-history") == true
    @State private var isAddingPeople = DemoOptions.screen == "chat-add-people"
    @State private var drafts = AttachmentDrafts()
    @State private var recorder = VoiceMessageRecorder()
    @State private var dictation = DictationController()
    @State private var isShowingVoiceHint = false
    @State private var isChoosingWhoToCall = DemoOptions.screen == "call-picker" || DemoOptions.screen == "chat-site-picker"
    @AppStorage("chatVoiceMode") private var isVoiceModePreferred = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var callCenter: CallCenter { appModel.callCenter }
    private var isThread: Bool { threadRootMessageId != nil }
    /// Where the call's stage ends on screen, and where the chat's content begins, so the messages start below the stage.
    @State private var callStageBottom: CGFloat = 0
    @State private var contentTop: CGFloat = 0

    var body: some View {
        Group {
            if let model {
                content(model)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { contentTop = $0 }
                    .overlay { if let call = stagedCall(model) { callStage(model, call) } }
            } else {
                ProgressView()
            }
        }
        .conversationBar(
            title: isThread ? "\(String(localized: "Thread")) \u{00B7} \(model?.title ?? String(localized: "Chat"))" : (model?.title ?? String(localized: "Chat")),
            onTitleTap: isThread || model?.room == nil ? nil : { isShowingInfo = true },
            isCallStageShown: model.map { stagedCall($0) != nil } ?? false
        )
        .navigationDestination(item: $openedThreadRootId) { rootId in
            ChatView(account: account, conversationId: conversationId, chatId: model?.chatId ?? chatId, threadRootMessageId: rootId)
        }
        // A message sent in the main history starts a thread, which opens so what the person says next goes in it.
        .onChange(of: model?.threadStartedBySend) { _, rootId in
            guard let rootId else { return }
            openedThreadRootId = rootId
            model?.threadStartedBySend = nil
        }
        .onChange(of: requestedThreadRootMessageId.wrappedValue, initial: true) { _, rootId in
            guard !isThread, let rootId else { return }
            openedThreadRootId = rootId
            requestedThreadRootMessageId.wrappedValue = nil
        }
        .toolbar {
            if !isThread, let model, canCall(model) {
                ToolbarItem(placement: .topBarTrailing) {
                    // A site chat holds everyone with access to the site, so a call there always starts with choosing who.
                    if model.room?.isSite == true {
                        Button { isChoosingWhoToCall = true } label: { Label("Choose who to call", systemImage: "phone") }
                            .accessibilityIdentifier("chatCallMenu")
                    } else {
                        Menu {
                            Button { startCall(model, userIds: nil, isVideoOn: false) } label: { Label("Voice call", systemImage: "phone") }
                            Button { startCall(model, userIds: nil, isVideoOn: true) } label: { Label("Video call", systemImage: "video") }
                            Button { isChoosingWhoToCall = true } label: { Label("Choose who to call", systemImage: "person.2") }
                        } label: { Label("Call", systemImage: "phone") }
                        .accessibilityIdentifier("chatCallMenu")
                    }
                }
            }
            if !isThread, let model, model.room != nil, stagedCall(model) == nil {
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
                    title: "Choose who to call", confirmTitle: "Call", people: model.reachablePeople.filter { $0.userId != model.currentUserId },
                    showsVideoChoice: true, maximumPeople: session.callMaximumPersonCount
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
            // The task runs again each time the screen comes back: the messages stay while `onAppear` reads them again.
            if let model, model.conversationId == conversationId { return }
            let chatModel = ChatModel(
                conversationId: conversationId, chatId: chatId, currentUserId: account.userId, connection: appModel.connection(for: account),
                socketFactory: appModel.socketFactory, threadRootMessageId: threadRootMessageId,
                offersMessageThreads: session.capabilities.offersMessageThreads,
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            chatModel.offersStructuredMentions = session.capabilities.offersStructuredMentions
            chatModel.offersInternalNotes = session.capabilities.offersInternalNotes
            chatModel.offersChatReferences = session.capabilities.offersChatReferences
            chatModel.onRead = { [session] id in session.noteChatRead(conversationId: id) }
            model = chatModel
            chatModel.start()
            if appModel.isDemo, DemoOptions.screen == "chat-composer" { drafts.stageDemo() }
            if appModel.isDemo, SpeechDemo.stagesListening(DemoOptions.screen, isThread: isThread) { dictation.stageListening(captionText: DemoSpeech.firstCaption) }
            if appModel.isDemo, SpeechDemo.stagesWords(DemoOptions.screen) { draft = DemoSpeech.dictatedWords }
            if appModel.isDemo, let messageId = SpeechDemo.messageToPlay(DemoOptions.screen, isThread: isThread) {
                // The chat or conversation under a thread stops any reading as it is covered, so the thread stages its own afterwards.
                if isThread { try? await Task.sleep(for: .seconds(2)) }
                session.readAloud.stageDemo(messageId: messageId)
            }
            if appModel.isDemo, DemoOptions.screen == "thread-chat-working" { chatModel.stageDemoWorking(inThreadOf: "t06") }
            if appModel.isDemo, CallDemo.owns(DemoOptions.screen) { CallDemo.markPlayed() }
            if appModel.isDemo, DemoOptions.screen == "chat-reply" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                chatModel.replyTarget = chatModel.timeline.messages.first { $0.authorUserId == "user02" }
            }
        }
        .onAppear {
            isOnScreen = true
            model?.start()
            if !isThread { callCenter.chatIdOnScreen = model?.chatId ?? chatId }
        }
        .onDisappear {
            isOnScreen = false
            model?.stop()
            // Another chat may already have taken the place.
            if !isThread, callCenter.chatIdOnScreen == (model?.chatId ?? chatId) { callCenter.chatIdOnScreen = nil }
        }
        .onChange(of: model?.chatId) { _, loadedChatId in
            if !isThread, isOnScreen, let loadedChatId { callCenter.chatIdOnScreen = loadedChatId }
        }
        // The feed stays open only while the chat is seen, which is how the server knows to send no notification for it.
        .onCoveredChange { isCovered in
            guard isOnScreen else { return }
            if isCovered {
                model?.stop()
                dictation.abort()
                session.readAloud.stop()
            } else {
                model?.start()
            }
        }
        .speechLifecycle(dictation)
    }

    @ViewBuilder
    private func content(_ model: ChatModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label(isThread ? LocalizedStringKey("Could not load this thread") : LocalizedStringKey("Could not load this chat"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.reload() } }
            }
        case .loaded:
            messages(model)
                .safeAreaInset(edge: .top, spacing: 0) { if !isThread { callBanner(model) } }
                // At rest the messages start below the call's stage; scrolled up, they fade out behind it. Reserved as a safe area
                // rather than a content margin: a margin pushed a short chat, which sits at the bottom, down under the composer.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if stagedCall(model) != nil { Color.clear.frame(height: max(callStageBottom - contentTop, 0)) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer(model) }
        }
    }

    private func messages(_ model: ChatModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: scrolling could leave a lazy stack placing its rows forever, with the app frozen at full CPU. The window
                // holds one page of messages and grows only when the person asks for earlier ones.
                VStack(alignment: .leading, spacing: 10) {
                    if model.window.earlierCount > 0 {
                        Button { Task { await model.loadEarlier() } } label: {
                            Text("\(model.window.earlierCount) earlier messages").font(.footnote).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoadingEarlier)
                    }
                    if model.timeline.messages.isEmpty, !isThread {
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
                            askDelete: { messageToDelete = $0 },
                            onOpenThread: threadOpener(model),
                            commentLine: commentLine(for: message, previous: previous, model: model)
                        )
                        .threadBar(
                            isShown: model.canOpenThreads && message.threadKey != nil,
                            joinsBelow: index + 1 < messages.count && messages[index + 1].threadKey == message.threadKey, gap: 10)
                        .background {
                            if highlightedMessageId == message.id {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.18)).padding(-4)
                            }
                        }
                        .id(message.id)
                        }
                        // The replies of a thread follow its root, which says how many there are.
                        if isThread, message.id == model.threadRootMessageId {
                            ThreadRepliesDivider(replyCount: messages.count - 1)
                        }
                    }
                    ForEach(model.questions) { card in
                        QuestionCardView(card: card, onAnswer: { answer in Task { await model.answer(card, with: answer) } }, onChatInstead: nil)
                    }
                    ForEach(model.approvals) { card in
                        ApprovalCardView(card: card) { isApproved in Task { await model.decide(card, isApproved: isApproved) } }
                    }
                    if model.isAssistantWorkingHere && model.questions.isEmpty && model.approvals.isEmpty {
                        TypingBubble()
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
            .task(id: focusedMessageId) { await showFocusedMessage(model, proxy: proxy) }
            .onChange(of: model.timeline.messages.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // The call's stage taking or giving back room at the top keeps the newest message in view above the composer. The
            // scroll waits for the layout that applies the new margin: made at once, it scrolls to where the end was before.
            .onChange(of: callStageBottom) { _, _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .overlay(alignment: .top) {
                if model.isFeedLost {
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

    /// The line above the first reply of a run in the main history: which message it comments on. Not shown right after the root or
    /// after another reply of the same thread.
    private func commentLine(for message: ChatMessage, previous: ChatMessage?, model: ChatModel) -> CommentLine? {
        guard model.canOpenThreads, let root = message.threadRootMessageId, previous?.id != root, previous?.threadRootMessageId != root,
            let rootMessage = model.timeline.messages.first(where: { $0.id == root }), !rootMessage.isDeleted
        else { return nil }
        let isOwn = rootMessage.authorUserId == model.currentUserId && !rootMessage.isAssistant
        let author: String? = isOwn ? nil : (rootMessage.isAssistant ? String(localized: "Assistant") : (rootMessage.authorName ?? model.member(rootMessage.authorUserId)?.shownName ?? String(localized: "Someone")))
        return CommentLine(rootMessageId: root, author: author, excerpt: ThreadExcerpt.start(of: rootMessage.text))
    }

    /// The message a link points at, when this screen is where it belongs: the thread it is in, or the whole chat.
    private var focusedMessageId: String? {
        guard let focus = session.messageToFocus, focus.conversationId == conversationId, focus.threadRootMessageId == threadRootMessageId else { return nil }
        return focus.messageId
    }

    /// Brings the message into view, reading earlier pages until it is held, and marks it briefly.
    private func showFocusedMessage(_ model: ChatModel, proxy: ScrollViewProxy) async {
        guard let messageId = focusedMessageId else { return }
        var pagesRead = 0
        while !model.timeline.messages.contains(where: { $0.id == messageId }), model.window.earlierCount > 0, pagesRead < 40 {
            await model.loadEarlier()
            pagesRead += 1
        }
        session.messageToFocus = nil
        guard model.timeline.messages.contains(where: { $0.id == messageId }) else {
            session.linkNotice = String(localized: "That message could not be found.")
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation { proxy.scrollTo(messageId, anchor: .center) }
        highlightedMessageId = messageId
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        highlightedMessageId = nil
    }

    /// Opens the thread of a message, on a server with threads and on the main history; nowhere else a reply opens one.
    private func threadOpener(_ model: ChatModel) -> ((String) -> Void)? {
        guard model.canOpenThreads else { return nil }
        return { openedThreadRootId = $0 }
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

    /// The call in this chat that the person is on, while its screen is put away: the chat shows it on its stage.
    private func stagedCall(_ model: ChatModel) -> ChatCallSession? {
        guard !isThread, let call = callCenter.session, !call.isEnded, !callCenter.isScreenShown, let chatId = model.chatId, call.chatId == chatId else { return nil }
        return call
    }

    /// Who the call is with, large over the chat: the other person, or in a group whoever is speaking, else the chat itself.
    private func callStage(_ model: ChatModel, _ call: ChatCallSession) -> some View {
        let others = call.participants.filter { !$0.isSelf && !$0.isRinging }
        let focus = others.count == 1 ? others.first : others.first(where: { $0.isSpeaking })
        return CallStage(
            name: focus?.name ?? model.title, status: call.statusText, isRecording: call.isTranscriptionOn,
            isSpeaking: focus?.isSpeaking ?? others.contains(where: { $0.isSpeaking }), isMuted: call.isMuted,
            onMute: { callCenter.setMuted(!call.isMuted) },
            leaveSymbol: "phone.down.fill", leaveLabel: "Leave call", onLeave: { callCenter.hangUp() },
            onStageBottom: { callStageBottom = $0 }, onAvatarTap: { callCenter.show() }, avatarTapLabel: "Return to the call"
        ) { size in
            if let focus {
                UserAvatar(userId: focus.userId, name: focus.name, size: size)
            } else if let room = model.room {
                ChatAvatar(room: room, size: size)
            } else {
                PersonAvatar(name: model.title, size: size)
            }
        }
    }

    @ViewBuilder
    private func callBanner(_ model: ChatModel) -> some View {
        // The stage shows the call this person is on; the banner is for a call they have not joined.
        if session.capabilities.offersChatCalls, stagedCall(model) == nil, let call = session.callBook.goingCall(inChat: model.chatId) {
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
        }
    }

    private func composer(_ model: ChatModel) -> some View {
        VStack(spacing: 6) {
            if session.readAloud.isShowingBar { ReadAloudBar(readAloud: session.readAloud) }
            if dictation.isShowingStatus { DictationStatus(dictation: dictation) }
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
                if model.canOpenThreads, model.replyTarget == nil, model.editTarget == nil,
                    let root = ThreadRouting.threadToContinue(model.timeline.messages, currentUserId: model.currentUserId)
                {
                    ContinueThreadHint(excerpt: ThreadRouting.excerpt(root.text)) {
                        openedThreadRootId = root.id
                    }
                    .padding(.horizontal, 12)
                }
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
                referenceList(model)
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
                    dictation: dictationControl(model), fieldIdentifier: "chatMessageField", sendIdentifier: "chatSendButton",
                    onEscape: {
                        guard draft.isEmpty, model.replyTarget != nil else { return false }
                        model.replyTarget = nil
                        return true
                    },
                    // A voice message is recorded instead of typed.
                    isInternalNote: model.isInternalNote,
                    menuItems: composerMenuItems(model),
                    onSend: {
                        // What is still being said belongs to the message that was sent, not to the next one.
                        dictation.abort()
                        let text = draft
                        draft = ""
                        Task { if await !model.send(text, attachments: drafts) { draft = text } }
                    }
                )
                }
                }
                .onChange(of: draft) { _, text in
                    if !text.isEmpty && model.editTarget == nil { model.noteTyping() }
                    model.searchReferences(for: text)
                }
                // The voice message bar takes the composer's place, with no microphone button to stop dictating.
                .onChange(of: isVoiceModePreferred) { _, _ in dictation.abort() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .onChange(of: model.editTarget) { _, target in
            if let target { draft = target.text }
        }
    }

    /// The microphone button, when the server has dictation set up for this person.
    private func dictationControl(_ model: ChatModel) -> DictationControl? {
        guard session.voiceAvailability.isDictationAvailable else { return nil }
        return DictationControl(isListening: dictation.isListening, isEnabled: model.canWrite && dictation.phase != .finishing) { toggleDictation() }
    }

    private func toggleDictation() {
        if callCenter.isInCall {
            dictation.report(String(localized: "You cannot dictate during a call."))
            return
        }
        session.readAloud.stop()
        dictation.toggle(place: .chat, connection: appModel.connection(for: account), isDemo: appModel.isDemo) { words in
            draft = DictationText.appending(words, to: draft)
        }
    }

    /// Voice messages are for a chat the person can write in, when the server has them and nothing else is being written.
    private func canUseVoice(_ model: ChatModel) -> Bool {
        (session.capabilities.offersVoiceMessages || (appModel.isDemo && DemoOptions.screen?.hasPrefix("chat-voice") == true)) && model.canWrite
            && model.editTarget == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drafts.items.isEmpty
    }

    /// What a send will do. In a chat with threads, a message in the main history starts a thread and one in a thread replies in it.
    private func fieldPrompt(_ model: ChatModel) -> LocalizedStringKey {
        if model.isInternalNote { return LocalizedStringKey("Internal note, staff only") }
        if isThread { return LocalizedStringKey("Reply in thread") }
        guard model.offersMessageThreads else {
            if !dynamicTypeSize.isAccessibilitySize, let agent = model.agents.first?.name { return LocalizedStringKey("Message, or @\(agent) to ask") }
            return LocalizedStringKey("Message")
        }
        return LocalizedStringKey("New thread")
    }

    /// The composer's [+] choices beyond attaching: a voice message, and for staff the internal-note lock, held on where the thread or the
    /// message replied to is internal.
    private func composerMenuItems(_ model: ChatModel) -> [ComposerMenuItem] {
        var items: [ComposerMenuItem] = []
        if canUseVoice(model) {
            items.append(ComposerMenuItem(title: "Voice message", systemImage: "mic.fill", identifier: "voiceModeButton") { isVoiceModePreferred = true })
        }
        if model.canPostInternal {
            items.append(
                ComposerMenuItem(
                    title: "Internal note", systemImage: "lock", identifier: "internalNoteToggle", isOn: model.isInternalNote,
                    isDisabled: model.isInternalNoteForced
                ) { model.isInternalNoteChosen.toggle() })
        }
        return items
    }

    /// The list that opens above the composer when the draft ends with a #: the tickets, controllers, virtual controllers, sites and
    /// cells the person can see, the chat's own suggestions for a bare #. A pick puts a ticket in as its number and the rest as links.
    @ViewBuilder
    private func referenceList(_ model: ChatModel) -> some View {
        if !model.referenceCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.referenceCandidates) { candidate in
                    Button {
                        draft = ChatReferences.inserting(candidate, into: draft)
                        model.clearReferenceCandidates()
                    } label: {
                        HStack(spacing: 10) {
                            ReferenceChip(reference: ChatReference(referenceKind: candidate.referenceKind, writtenText: nil, isAccessible: true, label: candidate.label))
                            if let detail = candidate.detailText, !detail.isEmpty {
                                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("referenceCandidate")
                }
            }
            .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
        }
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
                            let isStaff = candidate.kind == .user && model.member(candidate.id)?.isMujinUser == true
                            UserAvatar(userId: candidate.kind == .user ? candidate.id : nil, name: candidate.name, size: 32, isAssistant: candidate.kind == .agent, isStaff: isStaff)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.name).foregroundStyle(.primary).readsAsStaff(isStaff)
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

/// CommentLine is what the line above the first reply of a run says: the message it comments on.
struct CommentLine: Equatable {
    let rootMessageId: String
    /// Nil when the message is the person's own.
    let author: String?
    let excerpt: String
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
    /// Opens the thread of a message. Nil where a reply is quoted instead: in a thread, and on a server without threads.
    var onOpenThread: ((String) -> Void)?
    var commentLine: CommentLine?

    private var isMine: Bool { message.authorUserId == model.currentUserId && !message.isAssistant }

    var body: some View {
        if message.isDeleted {
            Text("This message was deleted")
                .font(.footnote)
                .italic()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if message.call != nil {
            // A call happened in the chat; nobody said it. It sits in the middle, whoever started it.
            VStack(spacing: 4) {
                tappableBubble
                if isMine, isLastOwn { receipt.frame(maxWidth: .infinity, alignment: .trailing) }
            }
            .frame(maxWidth: .infinity)
        } else {
        HStack(alignment: .top, spacing: 8) {
            // Others have a small round picture at the start of each run of their messages.
            if !isMine {
                if startsRun {
                    UserAvatar(
                        userId: message.authorUserId, name: message.authorName ?? model.member(message.authorUserId)?.shownName ?? "", size: 28,
                        isAssistant: message.isAssistant, isStaff: isAuthorStaff, surfaceColor: .portalPage)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine, startsRun { authorLine }
                if let commentLine, let onOpenThread {
                    ThreadCommentLine(author: commentLine.author, excerpt: commentLine.excerpt) { onOpenThread(commentLine.rootMessageId) }
                }
                if showsQuote { quote }
                tappableBubble
                if !openableReferences.isEmpty {
                    ReferenceChipRow(references: openableReferences) { path in
                        if let link = PortalLink(path: path) { appModel.openedLink = OpenedLink(link: link) }
                    }
                }
                // A link already shown as a reference chip gets no card of its own.
                ForEach((model.previews[message.id] ?? []).filter { card in !openableReferences.contains { $0.path == card.path && card.path != nil } }) { card in
                    LinkPreviewCardView(card: card, connection: model.connection)
                        .frame(maxWidth: 320)
                }
                if let onOpenThread, message.threadSummary?.isCountShown == true || isAssistantWorkingInThread {
                    ThreadReplyControl(summary: message.threadSummary, isWorking: isAssistantWorkingInThread) { onOpenThread(message.id) }
                }
                if isMine, isLastOwn { receipt }
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        }
    }

    /// The thread a tap on this message opens: the one it is a reply in, else its own, which a message with no replies starts.
    private var threadToOpen: String? {
        guard onOpenThread != nil else { return nil }
        return ThreadRouting.chatThreadToOpen(messageId: message.id, threadRootMessageId: message.threadRootMessageId, isDeleted: message.isDeleted)
    }

    /// A tap on a message that belongs to a thread opens the thread; links and buttons inside it keep working.
    @ViewBuilder
    private var tappableBubble: some View {
        if let root = threadToOpen, let onOpenThread {
            bubble.onTapGesture { onOpenThread(root) }
        } else {
            bubble
        }
    }

    /// The assistant is answering in the thread of this message while this screen does not show its typing dots, so the message
    /// carries them instead. The main history lists every reply and shows the dots itself, so one turn never shows two.
    private var isAssistantWorkingInThread: Bool {
        model.isOwnTurnRunning && !model.isAssistantWorkingHere && model.workingThreadRootMessageId == message.id
    }

    private var authorLine: some View {
        let member = model.member(message.authorUserId)
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Text(message.isAssistant ? ((message.authorName ?? "").isEmpty ? String(localized: "Assistant") : message.authorName!) : (message.authorName ?? member?.shownName ?? String(localized: "Someone")))
                .font(.caption.weight(.semibold))
                .portalNameLine()
                .readsAsStaff(isAuthorStaff)
            if message.isAssistant, let name = message.onBehalfOfUserName, !name.isEmpty {
                Text("for \(name)").font(.caption).foregroundStyle(.secondary).portalNameLine()
            }
            // The organization is shown beside a person from another one.
            if !message.isAssistant, let organization = message.authorOrganizationName ?? member?.organizationName, !organization.isEmpty,
                member?.organizationId != nil, member?.organizationId != model.member(model.currentUserId)?.organizationId
            {
                Text(organization).font(.caption).foregroundStyle(.secondary).portalNameLine()
            }
        }
    }

    /// Whether the author is Mujin staff, which their avatar's corner shows.
    private var isAuthorStaff: Bool { !message.isAssistant && (message.isAuthorMujinUser ?? model.member(message.authorUserId)?.isMujinUser) == true }

    /// A quote of the message right above, or of one the reader can see in the transcript, adds nothing.
    private var showsQuote: Bool {
        guard message.isReply, let replyId = message.replyToMessageId else { return false }
        if replyId == previousMessageId { return false }
        // In a thread every reply answers its root, which sits at the top of the screen.
        if replyId == model.threadRootMessageId { return false }
        let isRepliedMessageShown = model.timeline.messages.contains(where: { $0.id == replyId })
        if ThreadRouting.quoteRepeatsRoot(replyToMessageId: replyId, threadRootMessageId: message.threadRootMessageId, isRootShown: isRepliedMessageShown) { return false }
        if !message.hasQuotedText, isRepliedMessageShown { return false }
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

    /// The tickets, controllers, virtual controllers, sites and cells the message names that the reader may open, once each.
    private var openableReferences: [ChatReference] {
        message.isDeleted ? [] : message.references.filter(\.canOpen)
    }

    private var bubbleFill: AnyShapeStyle {
        if message.isInternal { return AnyShapeStyle(Color.statusWarning.opacity(0.16)) }
        return isMine ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(Color(.secondarySystemBackground))
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
                CallLineView(
                    call: call, currentUserId: model.currentUserId,
                    loadDetail: { [connection = model.connection] in try await connection.chatCall(id: call.id) },
                    openRecording: { recording in
                        Task {
                            guard let account = appModel.activeAccount else { return }
                            let address = await model.connection.server.endpoint("/api/v1/attachment/\(recording.id)")
                            await appModel.openInApp(address, account: account)
                        }
                    })
            } else {
            VStack(alignment: .leading, spacing: 2) {
                // People's messages are Markdown. The words around code and links keep the name chips of the people mentioned.
                RichBodyView(markdown: message.text, connection: model.connection, isSelectable: false) { words in markdownText(words) }
                if message.isEdited {
                    Text("edited").font(.caption2).foregroundStyle(AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            // An internal note is amber and outlined, so a person's own note does not look like what customers read.
            .overlay {
                if message.isInternal {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.statusWarning, lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if message.isInternal { InternalNoteLabel().padding(6) }
            }
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

    /// The words of a message as Markdown. One paragraph hugs its text, as a bubble does; anything with blocks (a list, a quote, code,
    /// a table) uses the width the bubble has.
    @ViewBuilder
    private func markdownText(_ words: String) -> some View {
        let text = MentionText.rendered(words, members: model.room?.members ?? [], agents: model.agents)
        if case .paragraph(let paragraph)? = MarkdownBlocks.parse(text).first, MarkdownBlocks.parse(text).count == 1 {
            Text(MarkdownView.chips(MarkdownView.inline(paragraph), names: model.mentionNames, isOnAccent: isMine))
        } else {
            MarkdownView(markdown: text, isSelectable: false, mentionNames: model.mentionNames, isOnAccent: isMine)
        }
    }

    /// Copies the address of the message: `/chat/<chatId>/<messageId>` on the account's server.
    private var copyLinkAction: (() -> Void)? {
        guard let chatId = model.chatId, let server = appModel.activeAccount?.server else { return nil }
        let address = MessagePermalink.chatMessage(server: server, chatId: chatId, messageId: message.id).absoluteString
        return { UIPasteboard.general.string = address }
    }

    /// What a long press on the message offers. A person reacts to anyone's message; the rest follows what the room allows.
    private var heldActions: MessageActions {
        let hasPreviews = !(model.previews[message.id] ?? []).isEmpty
        return MessageActions(
            messageId: message.id, text: message.text, isTrailing: isMine,
            ownReaction: Reactions.summaries(model.timeline.reactions(for: message.id), currentUserId: model.currentUserId).first { $0.isMine }?.emoji,
            onReact: { emoji in Task { await model.react(messageId: message.id, emoji: emoji) } },
            onReply: model.canWrite ? { if let onOpenThread { onOpenThread(threadToOpen ?? message.id) } else { model.replyTarget = message } } : nil,
            onEdit: model.canEdit(message) ? { model.editTarget = message } : nil,
            onRemoveLinkPreviews: isMine && hasPreviews ? { Task { await model.removePreviews(of: message) } } : nil,
            onDelete: model.canDelete(message) ? { askDelete(message) } : nil,
            onCopyLink: copyLinkAction,
            // A voice message has its own player, and a call line has no words.
            readAloudText: message.voice == nil && message.call == nil && !message.isDeleted ? message.text : nil)
    }

    @ViewBuilder
    private var receipt: some View {
        let count = model.timeline.readerCount(of: message.id, excluding: model.currentUserId)
        if count > 0, model.room?.isSite != true {
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
    @State private var searchText = ""
    @State private var isShowingCalls = DemoOptions.screen == "chat-call-history" || DemoOptions.screen == "chat-call-history-detail"

    /// The people to show: a site chat can hold hundreds, so it can be searched.
    private func shownMembers(of room: ChatRoom) -> [ChatMember] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard room.isSite, !text.isEmpty else { return room.currentMembers }
        return room.currentMembers.filter { $0.shownName.localizedCaseInsensitiveContains(text) || ($0.organizationName ?? "").localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            List { PortalRows {
                if let room = model.room {
                    Section {
                        ForEach(shownMembers(of: room)) { member in
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
                    } header: {
                        Text(room.isSite ? "\(room.currentMembers.count) people" : "People")
                    } footer: {
                        if room.isSite { Text("Anyone with access to this site can join by opening this chat or being mentioned in it.") }
                    }
                    if session.capabilities.offersChatCallHistory, model.chatId != nil {
                        Section {
                            NavigationLink { ChatCallsView(model: model) } label: { Label("Calls", systemImage: "phone") }
                                .accessibilityIdentifier("chatCallsRow")
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
                    if room.hasManyAuthors, room.canWrite {
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
            .navigationDestination(isPresented: $isShowingCalls) { ChatCallsView(model: model) }
            .searchablePeople(isOn: model.room?.isSite == true, text: $searchText)
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
        let isStaff = member.isMujinUser == true
        if !dynamicTypeSize.isAccessibilitySize { UserAvatar(userId: member.userId, name: member.shownName, size: 32, isStaff: isStaff) }
        VStack(alignment: .leading, spacing: 2) {
            let nameLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
            nameLayout {
                // With no avatar shown, the mark follows the name.
                Text(isViewer ? String(localized: "You") : member.shownName).portalNameLine().readsAsStaff(isStaff && !dynamicTypeSize.isAccessibilitySize)
                if isStaff, dynamicTypeSize.isAccessibilitySize {
                    StaffBadge()
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
