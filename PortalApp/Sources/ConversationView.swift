import PortalKit
import SwiftUI
import UIKit

/// ConversationView is one conversation: the transcript with the answer
/// streaming in, question and approval cards, and the composer. On a server with message threads a reply goes in a thread: the
/// transcript shows how many replies a message has, and a tap opens the thread as a screen of its own, which is this same view with
/// a `threadRootMessageId`.
struct ConversationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account
    let conversationId: String
    let title: String?
    /// Told when the server gives the conversation a new title, so the list shows it too.
    var onTitleChanged: ((String) -> Void)?
    /// The message whose thread this screen shows alone, with its own composer. Nil for the whole conversation.
    var threadRootMessageId: String?
    /// A thread a notification asks this conversation to open on, which this view takes and clears.
    var requestedThreadRootMessageId: Binding<String?> = .constant(nil)

    @State private var model: ConversationModel?
    @State private var openedThreadRootId: String?
    @State private var voice: VoiceCallController?
    @State private var dictation = DictationController()
    @State private var draft = ""
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var fullArtifact: ArtifactReference?
    @AppStorage(AssistantDisplay.showWorkingNotesKey) private var showWorkingNotes = false
    @State private var isShowingArtifacts = false
    @State private var isShowingBackgroundCommands = false
    @State private var drafts = AttachmentDrafts()
    @State private var isOnScreen = false
    /// Whether the top of the thread is in view, where earlier messages load.
    /// How far a pull past the top has gone toward reading earlier messages, from 0 to 1.
    @State private var earlierPullProgress = 0.0
    /// Whether this screen is counted among those that show a call going elsewhere in a strip under their header.
    @State private var isHostingCallStrip = false
    /// Whether the conversation already opened on the thread where something waited, which it does once.
    @State private var hasOpenedWaitingThread = false

    private var isThread: Bool { threadRootMessageId != nil }
    /// Whether a call can start here: from the conversation, or from a thread on a server with threads, where it goes in the thread.
    private var canCall: Bool { !isThread || session.capabilities.offersMessageThreads }
    /// Where the call's stage ends on screen, and where the conversation's content begins, so the messages start below the stage.
    @State private var callStageBottom: CGFloat = 0
    @State private var contentTop: CGFloat = 0

    /// Whether a call with the assistant is going or being set up: the conversation shows it on its stage.
    private var isCallStaged: Bool {
        guard let voice else { return false }
        return voice.isActive || voice.phase != .idle
    }

    /// The artifacts whose cards this view's messages show.
    private var shownArtifactCardIds: Set<String> {
        Set((model?.transcript.displayEntries ?? []).compactMap { entry in
            if case .produced(.artifact(let artifact)) = entry { return artifact.id }
            return nil
        })
    }

    /// The first words of a thread's root, for the line that points to it.
    private func threadExcerpt(_ rootId: String, _ model: ConversationModel) -> String? {
        for entry in model.transcript.entries {
            switch entry {
            case .assistant(let id, let text, _) where id == rootId: return ThreadRouting.excerpt(text)
            case .user(let id, let text, _) where id == rootId: return ThreadRouting.excerpt(text)
            default: continue
            }
        }
        return nil
    }

    /// Starts a call. A call and dictation both want the microphone, and a call wins.
    private func startCall() {
        guard let voice else { return }
        dictation.abort()
        session.readAloud.stop()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        holdCall()
        Task { await voice.start() }
    }

    /// Hands the call to the session, which keeps it, with this conversation or thread, when the screen goes away. A call that is going
    /// already, with the assistant or with people, ends first: one call at a time.
    private func holdCall() {
        guard let voice, let model else { return }
        if let other = session.assistantCall, other.voice !== voice { other.end() }
        if let peopleCall = appModel.callCenter.session, !peopleCall.isEnded { appModel.callCenter.hangUp() }
        session.assistantCall = AssistantCall(conversationId: conversationId, threadRootMessageId: threadRootMessageId, model: model, voice: voice)
    }

    /// Where this screen is, as a call's place: the conversation, or one of its threads.
    private var place: CallPlace { CallPlace(conversationId: conversationId, threadRootMessageId: threadRootMessageId) }

    /// The assistant large over the conversation while the call goes, with what the call is doing under its name, and leave and
    /// mute at the top right. A tap on the picture cuts a playing answer short where that is possible.
    private func assistantCallStage(_ voice: VoiceCallController, isThinking: Bool) -> some View {
        CallStage(
            name: String(localized: "Assistant"), status: Self.callStatus(voice, isThinking: isThinking),
            isSpeaking: voice.phase == .speaking, isMuted: voice.isMuted,
            onMute: voice.isActive ? { voice.toggleMute() } : nil,
            leaveSymbol: voice.isActive ? "phone.down.fill" : "xmark", leaveLabel: voice.isActive ? "End the call" : "Close",
            onLeave: { voice.end() }, onStageBottom: { callStageBottom = $0 },
            onAvatarTap: voice.canCutIn ? { voice.cutAnswer() } : nil, avatarTapLabel: "Stop the answer"
        ) { size in
            AssistantCallAvatar(size: size)
        }
        .sensoryFeedback(trigger: voice.phase) { _, new in new == .listening ? .impact(weight: .light) : nil }
    }

    /// Only the state, or a problem.
    private static func callStatus(_ voice: VoiceCallController, isThinking: Bool) -> String {
        switch voice.phase {
        case .idle: ""
        case .connecting: String(localized: "Connecting\u{2026}")
        case .failed(let message): message
        case .speaking: String(localized: "Speaking")
        case .listening:
            if let notice = voice.notice { notice }
            else if voice.isMuted { String(localized: "Muted") }
            else if isThinking { String(localized: "Thinking") }
            else { String(localized: "Listening") }
        }
    }

    var body: some View {
        Group {
            if let model {
                content(model)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { contentTop = $0 }
                    .overlay { if let voice, isCallStaged { assistantCallStage(voice, isThinking: model.isRunning) } }
            } else {
                ProgressView()
            }
        }
        // A call going on elsewhere, with the assistant or with people, shows under the header, threads included.
        .safeAreaInset(edge: .top, spacing: 0) { if !isCallStaged { OngoingCallStrip(place: place) } }
        .conversationBar(title: isThread ? "\(String(localized: "Thread")) \u{00B7} \(shownTitle)" : shownTitle, isCallStageShown: isCallStaged)
        // A call that ended on this screen is no longer the session's to keep.
        .onChange(of: isCallStaged) { _, isStaged in
            if !isStaged, let voice, session.assistantCall?.voice === voice { session.assistantCall = nil }
        }
        .navigationDestination(item: $openedThreadRootId) { rootId in
            ConversationView(account: account, conversationId: conversationId, title: title, threadRootMessageId: rootId)
        }
        // A conversation whose questions and approvals wait only in a thread opens on that thread, once.
        .onChange(of: model?.threadToOpenOn) { _, rootId in
            guard !isThread, !hasOpenedWaitingThread, let rootId else { return }
            hasOpenedWaitingThread = true
            openedThreadRootId = rootId
        }
        .onChange(of: requestedThreadRootMessageId.wrappedValue, initial: true) { _, rootId in
            guard !isThread, let rootId else { return }
            openedThreadRootId = rootId
            requestedThreadRootMessageId.wrappedValue = nil
        }
        .toolbar {
            // A thread lists the pages and files made in it.
            if isThread {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingArtifacts = true } label: { Label("Pages and files it made", systemImage: "doc.richtext") }
                        .accessibilityIdentifier("threadArtifactsButton")
                }
            }
            // The header shows a terminal while this view, the main history or this thread, has a command running, with how many.
            if let count = model?.runningBackgroundCommandCount, count > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingBackgroundCommands = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "apple.terminal")
                            Text(verbatim: "\(count)").font(.subheadline.monospacedDigit())
                        }
                    }
                    .accessibilityLabel(Text("Background commands, \(count) running"))
                    .accessibilityIdentifier("backgroundCommandsButton")
                }
            }
            // The call sits beside the conversation's menu, in the same capsule; in a thread, alone, and the call goes in the thread.
            if !isCallStaged, voice != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startCall() } label: { Label("Call the assistant", systemImage: "phone") }
                        .accessibilityIdentifier("assistantCallButton")
                }
            }
            if !isThread, !isCallStaged {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !isMainChat, session.capabilities.offersMainChatChoice {
                        Button {
                            Task { await makeMainChat() }
                        } label: {
                            Label("Make main chat", systemImage: "star")
                        }
                    }
                    if !isMainChat {
                        Button {
                            renameDraft = shownTitle
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
                    Button {
                        isShowingArtifacts = true
                    } label: {
                        Label("Pages and files it made", systemImage: "doc.richtext")
                    }
                } label: {
                    Label("Conversation options", systemImage: "ellipsis.circle")
                }
            }
            }
        }
        .alert("Rename conversation", isPresented: $isRenaming) {
            TextField("Title", text: $renameDraft)
            Button("Save") { Task { await model?.rename(to: renameDraft) } }
            Button("Cancel", role: .cancel) {}
        }
        .attachmentPickers(drafts)
        .sheet(isPresented: $isShowingBackgroundCommands) {
            if let model { BackgroundCommandsSheet(model: model, currentUserId: account.userId) }
        }
        .sheet(isPresented: $isShowingArtifacts) {
            ArtifactListSheet(
                conversationId: conversationId, threadRootMessageId: threadRootMessageId, cardArtifactIds: shownArtifactCardIds,
                connection: appModel.connection(for: account)
            ) { artifact in
                isShowingArtifacts = false
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    fullArtifact = artifact
                }
            }
        }
        .fullScreenCover(item: $fullArtifact) { artifact in
            ArtifactFullView(artifact: artifact, connection: appModel.connection(for: account))
        }
        // The main chat may already be open when an Ask button is tapped, on a tab that was not showing.
        .onChange(of: session.referenceHandoff.conversationId) { _, _ in takeReference() }
        .onChange(of: session.selectedSection) { _, _ in takeReference() }
        .onAppear { takeReference() }
        .task(id: conversationId) {
            // A call with this conversation that went on while it was off screen: the screen takes it back, with its conversation.
            if let call = session.assistantCall, call.place == place, call.isGoing {
                model = call.model
                voice = call.voice
                call.model.start()
                return
            }
            // The task runs again each time the screen comes back: the messages stay while `onAppear` reads them again.
            if let model, model.conversationId == conversationId {
                // A call is made from the conversation or from one of its threads, on a server whose threads have their own runs.
                if canCall, !isCallStaged { voice = VoiceCallController(model: model, connection: appModel.connection(for: account), socketFactory: URLSessionVoiceSocket.factory) }
                return
            }
            let conversationModel = ConversationModel(
                conversationId: conversationId, currentUserId: account.userId, connection: appModel.connection(for: account),
                socketFactory: appModel.socketFactory, threadRootMessageId: threadRootMessageId,
                offersMessageThreads: session.capabilities.offersMessageThreads,
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            conversationModel.onTitleChanged = { onTitleChanged?($0) }
            conversationModel.offersTodos = session.capabilities.offersTodos
            conversationModel.offersBackgroundCommands = session.capabilities.offersBackgroundCommands
            model = conversationModel
            takeReference()
            // The screen moves to another conversation (on iPad, a pick from the list): a call that is going stays with the session.
            if !isCallStaged { voice?.end() }
            if canCall {
                voice = VoiceCallController(
                    model: conversationModel, connection: appModel.connection(for: account), socketFactory: URLSessionVoiceSocket.factory)
            }
            conversationModel.start()
            if appModel.isDemo, DemoOptions.screen == "voice" {
                voice?.startDemo()
                holdCall()
            }
            if appModel.isDemo, DemoOptions.screen == "conversation-composer" { drafts.stageDemo() }
            if appModel.isDemo, SpeechDemo.stagesListening(DemoOptions.screen, isThread: isThread) { dictation.stageListening(captionText: DemoSpeech.firstCaption) }
            if appModel.isDemo, SpeechDemo.stagesWords(DemoOptions.screen) { draft = DemoSpeech.dictatedWords }
            if appModel.isDemo, let messageId = SpeechDemo.messageToPlay(DemoOptions.screen, isThread: isThread) {
                // The chat or conversation under a thread stops any reading as it is covered, so the thread stages its own afterwards.
                if isThread { try? await Task.sleep(for: .seconds(2)) }
                session.readAloud.stageDemo(messageId: messageId)
            }
            if appModel.isDemo, DemoOptions.screen == "conversation-reply" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                conversationModel.replyTarget = ReplyReference(
                    messageId: "m02", authorName: "Assistant", excerpt: "Here is the summary for this week. Three sites are healthy, one needs attention.")
            }
        }
        .onAppear {
            isOnScreen = true
            model?.start()
            session.callPlaceOnScreen = place
            if !isHostingCallStrip {
                isHostingCallStrip = true
                session.callStripHostCount += 1
            }
        }
        .onDisappear {
            isOnScreen = false
            if session.callPlaceOnScreen == place { session.callPlaceOnScreen = nil }
            if isHostingCallStrip {
                isHostingCallStrip = false
                session.callStripHostCount -= 1
            }
            // A call goes on in its bar, its conversation still listening for the answers; anything else stops with the screen.
            guard !isCallStaged else { return }
            model?.stop()
            voice?.end()
        }
        .speechLifecycle(dictation)
        .onCoveredChange { isCovered in
            guard isOnScreen, let model else { return }
            if isCovered {
                dictation.abort()
                session.readAloud.stop()
                // A call goes on in its bar while the screen is covered.
                guard !isCallStaged else { return }
                model.stop()
                voice?.end()
            } else {
                if !isThread, !isCallStaged {
                    voice = VoiceCallController(model: model, connection: appModel.connection(for: account), socketFactory: URLSessionVoiceSocket.factory)
                }
                model.start()
            }
        }
    }

    /// Puts the reference an Ask button named into the composer, once the model exists.
    private func takeReference() {
        guard !isThread, let model, let pending = session.referenceHandoff.conversationId == conversationId ? session.referenceHandoff.pending : nil else { return }
        _ = session.referenceHandoff.take(for: conversationId)
        model.viewingReference = (pending.viewing, pending.subject)
    }

    private var shownTitle: String {
        if isMainChat { return String(localized: "Main chat") }
        if let modelTitle = model?.title, !modelTitle.isEmpty { return modelTitle }
        if let title, !title.isEmpty { return title }
        return String(localized: "New conversation")
    }

    /// The main chat is named by the app, in the person's language, and cannot be renamed.
    private func makeMainChat() async {
        do {
            try await appModel.connection(for: account).setMainConversation(id: conversationId)
            model?.becameMain()
            session.noteMainChat(conversationId: conversationId)
        } catch {
            appModel.handle(error, account: account)
        }
    }

    private var isMainChat: Bool { model?.isMain == true || session.knownMainConversationId == conversationId }


    @ViewBuilder
    private func content(_ model: ConversationModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label(isThread ? LocalizedStringKey("Could not load this thread") : LocalizedStringKey("Could not load this conversation"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.reload() } }
            }
        case .loaded:
            transcript(model)
                // At rest the messages start below the call's stage; scrolled up, they fade out behind it. Reserved as a safe area
                // rather than a content margin: a margin pushed a short conversation, which sits at the bottom, down under the composer.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isCallStaged { Color.clear.frame(height: max(callStageBottom - contentTop, 0)) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        // The todo list of this view, the main history's or this thread's, above where the person writes.
                        if !model.shownTodos.isEmpty { TodoPanel(todos: model.shownTodos) }
                        ComposerBar(model: model, voice: voice, dictation: dictation, drafts: drafts, draft: $draft, onTalk: voice == nil ? nil : { startCall() })
                    }
                }
        }
    }

    /// Reads the page before the first message held, then brings the first row shown before back to the top of the screen, so what
    /// was being read stays where it was and the earlier messages wait above it.
    private func loadEarlierKeepingPlace(_ model: ConversationModel, proxy: ScrollViewProxy) {
        let firstShown = model.transcript.displayEntries.first { Self.isShown($0, showWorkingNotes: showWorkingNotes) }?.id
        Task {
            await model.loadEarlier()
            guard let firstShown else { return }
            proxy.scrollTo(firstShown, anchor: .top)
        }
    }

    /// The row at the top of the messages, or nil where it would say nothing useful: an empty conversation, or the start of a thread,
    /// whose root is at the top.
    private func earlierRowState(_ model: ConversationModel) -> EarlierMessages.RowState? {
        let state = model.earlierRowState
        if state == .start, model.isThread || model.transcript.entries.isEmpty { return nil }
        return state
    }

    private func transcript(_ model: ConversationModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: rows measured only as they scroll in left the thread blank for a moment on the way to its end, and could
                // leave a lazy stack placing its rows forever. The window holds one page of messages and grows a page at a time.
                VStack(alignment: .leading, spacing: 16) {
                    // Earlier messages are read on a pull past the top, which this row says.
                    if let state = earlierRowState(model) {
                        EarlierMessagesRow(state: state, pullProgress: earlierPullProgress) { loadEarlierKeepingPlace(model, proxy: proxy) }
                    }
                    if model.transcript.entries.isEmpty, !model.isThread {
                        ContentUnavailableView {
                            Label("Ask anything", systemImage: "sparkles")
                        } description: {
                            Text("Your assistant can look things up and take actions with your approval.")
                        }
                        .padding(.top, 48)
                    }
                    let shownEntries = model.transcript.displayEntries.filter { Self.isShown($0, showWorkingNotes: showWorkingNotes) }
                    let threadKeys = Self.threadKeys(of: shownEntries, in: model.transcript)
                    ForEach(Array(shownEntries.enumerated()), id: \.element.id) { index, entry in
                        TranscriptRow(
                            entry: entry, model: model,
                            openArtifact: { fullArtifact = $0 },
                            onOpenThread: threadOpener(model),
                            commentLine: commentLine(
                                for: entry, previous: shownEntries[..<index].last { Self.messageId(of: $0) != nil }, entries: shownEntries, model: model)
                        )
                        .threadBar(
                            isShown: model.canOpenThreads && threadKeys[index] != nil,
                            joinsBelow: index + 1 < threadKeys.count && threadKeys[index + 1] == threadKeys[index], gap: 16)
                        .modifier(RenderedMessageIdentifier(messageId: String(entry.id.split(separator: ":").last ?? "")))
                        .id(entry.id)
                        // The replies of a thread follow its root, which says how many there are.
                        if let rootId = model.threadRootMessageId, entry.id == "user:\(rootId)" || entry.id == "assistant:\(rootId)" {
                            ThreadRepliesDivider(
                                replyCount: max(
                                    model.transcript.threadSummary(for: rootId)?.replyCount ?? 0,
                                    shownEntries.filter { Self.isReply(in: $0, root: rootId) }.count))
                        }
                    }
                    // The one sign of a turn at work: typing dots below everything, until the answer is done.
                    // A question or an approval that waits in a thread: one line here, which opens it.
                    if !model.isThread {
                        ForEach(model.waitingThreadRootIds, id: \.self) { rootId in
                            WaitingInThreadLine(excerpt: threadExcerpt(rootId, model)) { openedThreadRootId = rootId }
                        }
                    }
                    if model.isShowingTypingDots {
                        TypingBubble().id("typing")
                    }
                    if !model.isThread {
                        ForEach(model.backgroundWork) { work in
                            BackgroundWorkBanner(work: work) { Task { await model.stopBackgroundWork(work) } }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Readable width: the column stops growing on wide screens.
                .frame(maxWidth: Self.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.portalPage)
            // A short thread starts at the top; a long one opens, and follows, at the end.
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // The bottom anchor keeps the reading place as earlier messages go in above.
            .modifier(PullForEarlier(state: model.earlierRowState, pullProgress: $earlierPullProgress) { loadEarlierKeepingPlace(model, proxy: proxy) })
            // The end of the thread, which an answer being written changes. Reading the same messages again moves nothing.
            .onChange(of: model.transcript.entries.last) { _, _ in
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
                        .accessibilityIdentifier("reconnecting")
                }
            }
        }
    }

    static let readableWidth: CGFloat = 720

    /// The thread each entry is part of, which the bar beside it follows. What the assistant does after a message of a thread (its
    /// tool calls, a failed turn) is part of that thread until the next message.
    private static func threadKeys(of entries: [TranscriptEntry], in transcript: Transcript) -> [String?] {
        var current: String?
        return entries.map { entry in
            if let id = messageId(of: entry) { current = transcript.threadKey(ofMessage: id) }
            return current
        }
    }

    /// The message id of an entry that is a message, else nil.
    private static func messageId(of entry: TranscriptEntry?) -> String? {
        switch entry {
        case .user(let id, _, _)?: id
        case .assistant(let id, _, _)?: id
        default: nil
        }
    }

    /// The line above the first reply of a run in the main history: which message it comments on. Not shown when the message above
    /// it, passing over any step rows between them, is the root or another reply of the same thread.
    private func commentLine(for entry: TranscriptEntry, previous: TranscriptEntry?, entries: [TranscriptEntry], model: ConversationModel) -> CommentLine? {
        guard model.canOpenThreads, let id = Self.messageId(of: entry), let root = model.transcript.replyThreadRoot(of: id) else { return nil }
        if let previousId = Self.messageId(of: previous), previousId == root || model.transcript.replyThreadRoot(of: previousId) == root { return nil }
        for candidate in entries {
            switch candidate {
            case .user(let rootId, let text, _) where rootId == root:
                return CommentLine(rootMessageId: root, author: nil, excerpt: ThreadExcerpt.start(of: text))
            case .assistant(let rootId, let text, _) where rootId == root:
                return CommentLine(rootMessageId: root, author: String(localized: "Assistant"), excerpt: ThreadExcerpt.start(of: text))
            default: continue
            }
        }
        return nil
    }

    /// Opens the thread of a message, on a server with threads and on the main history; nowhere else a reply opens one.
    private func threadOpener(_ model: ConversationModel) -> ((String) -> Void)? {
        guard model.canOpenThreads else { return nil }
        return { openedThreadRootId = $0 }
    }

    /// Whether an entry of a thread's transcript is something said in reply: what the person or the assistant wrote after the root.
    private static func isReply(in entry: TranscriptEntry, root: String) -> Bool {
        switch entry {
        case .user(let id, _, _): id != root
        case .assistant(let id, _, _): id != root
        default: false
        }
    }

    /// Bookkeeping notes are not drawn, so they leave no gap either.
    /// Whether a row of the transcript is drawn. The "What it did" rows only when the person turned them on in the assistant settings.
    private static func isShown(_ entry: TranscriptEntry, showWorkingNotes: Bool) -> Bool {
        switch entry {
        case .note(_, let note):
            if case .backgroundNotice = note { return true }
            return false
        case .tool(let activity): return showWorkingNotes || activity.isThinkingHarder
        case .toolGroup: return showWorkingNotes
        default: return true
        }
    }

    private static func isStreamingOrCard(_ entry: TranscriptEntry) -> Bool {
        switch entry {
        case .assistant(_, _, let isStreaming): isStreaming
        case .question, .approval: true
        default: false
        }
    }
}

/// AssistantBubbleKey is everything an assistant bubble draws; it is drawn again only when one of them changes.
private struct AssistantBubbleKey: Equatable {
    let id: String
    let text: String
    let isStreaming: Bool
    let reactions: [Reaction]
    let speakFirstReason: String?
    let speakFirstOutcome: String?
    let threadRoot: String?
}

private struct TranscriptRow: View {
    /// Bubbles stop growing here, so a wide iPad window keeps readable lines.
    static let bubbleWidth: CGFloat = 620
    @Environment(AppModel.self) private var appModel
    let entry: TranscriptEntry
    let model: ConversationModel
    let openArtifact: (ArtifactReference) -> Void
    /// Opens the thread of a message. Nil where a reply is quoted instead: in a thread, and on a server without threads.
    var onOpenThread: ((String) -> Void)?
    var commentLine: CommentLine?

    /// The line above a reply that says which message it comments on.
    @ViewBuilder
    private var commentLineView: some View {
        if let commentLine, let onOpenThread {
            ThreadCommentLine(author: commentLine.author, excerpt: commentLine.excerpt) { onOpenThread(commentLine.rootMessageId) }
        }
    }

    /// The count of replies under a message, or that the assistant is answering in its thread. A turn whose answer this screen shows
    /// has the typing dots at the end of the history, so the message does not say it again.
    @ViewBuilder
    private func threadControl(for id: String) -> some View {
        let isWorking = model.isRunning && !model.isRunningHere && model.transcript.workingThreadRootMessageId == id
        let summary = model.transcript.threadSummary(for: id)
        if let onOpenThread, summary?.isCountShown == true || isWorking {
            ThreadReplyControl(summary: summary, isWorking: isWorking) { onOpenThread(id) }
        }
    }

    /// The thread a tap on a message opens: the one it is a reply in, else its own once it is stored.
    private func threadToOpen(for id: String) -> String? {
        onOpenThread == nil ? nil : model.transcript.threadToOpen(forMessage: id)
    }

    /// Copies the address of a message: `/chat/<conversationId>#message-<messageId>` on the account's server. Nil until it is stored.
    private func copyLinkAction(for id: String) -> (() -> Void)? {
        guard !id.hasPrefix("pending:"), let server = appModel.activeAccount?.server else { return nil }
        let address = MessagePermalink.assistantMessage(server: server, conversationId: model.conversationId, messageId: id).absoluteString
        return { UIPasteboard.general.string = address }
    }

    /// What a long press on the person's own message offers: answering it and working with its words.
    private func userActions(id: String, text: String) -> MessageActions {
        MessageActions(
            messageId: id, text: text, isTrailing: true, ownReaction: nil, onReact: nil,
            onReply: { if let onOpenThread { onOpenThread(threadToOpen(for: id) ?? id) } else { model.replyTarget = ReplyReference(messageId: id, authorName: "", excerpt: text, isOwn: true) } },
            onEdit: nil, onRemoveLinkPreviews: nil, onDelete: nil, onCopyLink: copyLinkAction(for: id), readAloudText: text)
    }

    /// What a long press on an answer offers: reacting to it, answering it and working with its words.
    private func assistantActions(id: String, text: String) -> MessageActions {
        MessageActions(
            messageId: id, text: text, isTrailing: false,
            ownReaction: Reactions.summaries(model.transcript.reactions(for: id), currentUserId: model.currentUserId).first { $0.isMine }?.emoji,
            onReact: { emoji in Task { await model.react(messageId: id, emoji: emoji) } },
            onReply: {
                if let onOpenThread { onOpenThread(threadToOpen(for: id) ?? id) } else { model.replyTarget = ReplyReference(messageId: id, authorName: String(localized: "Assistant"), excerpt: text) }
            },
            onEdit: nil, onRemoveLinkPreviews: nil, onDelete: nil, onCopyLink: copyLinkAction(for: id), readAloudText: text)
    }

    /// The cards under a message that holds a link, as under a message in a people chat.
    @ViewBuilder
    private func linkCards(for id: String) -> some View {
        // While the server is still asked about a link, its card's space is held, so the row does not grow later.
        if model.linkPreviews.isAwaiting(id) {
            Color.clear.frame(height: 88)
        }
        ForEach(model.linkPreviews.previews[id] ?? []) { card in
            LinkPreviewCardView(card: card, connection: model.connection)
                .frame(maxWidth: 320)
        }
    }

    var body: some View {
        switch entry {
        case .user(let id, let text, let viewing):
            VStack(alignment: .trailing, spacing: 4) {
                commentLineView
                if let quote = model.transcript.replyQuote(for: id), !(commentLine != nil && quote.messageId == commentLine?.rootMessageId) {
                    SentQuote(authorName: quote.authorName, excerpt: quote.excerpt)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack {
                    Spacer(minLength: 48)
                    // The person's side in the accent's tint with primary text, as in Messages.
                    HoldableMessage(actions: id.hasPrefix("pending:") ? nil : userActions(id: id, text: text)) {
                        Text(MarkdownView.plain(text))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .modifier(OpensThread(root: threadToOpen(for: id), onOpen: onOpenThread))
                    .reactionCorner(model.transcript.reactions(for: id), currentUserId: model.currentUserId, isLeading: false, onTap: nil)
                }
                if let viewing {
                    ViewingChip(viewing: viewing)
                }
                linkCards(for: id)
                threadControl(for: id)
            }
            .frame(maxWidth: Self.bubbleWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant(let id, let text, let isStreaming):
            VStack(alignment: .leading, spacing: 4) {
            commentLineView
            HStack {
                let speakFirstReason = model.isOwnConversation ? model.transcript.speakFirstReason(for: id) : nil
                StableBubble(key: AssistantBubbleKey(id: id, text: text, isStreaming: isStreaming, reactions: model.transcript.reactions(for: id), speakFirstReason: speakFirstReason, speakFirstOutcome: model.speakFirstOutcome, threadRoot: threadToOpen(for: id))) {
                HoldableMessage(actions: isStreaming ? nil : assistantActions(id: id, text: text)) {
                    VStack(alignment: .leading, spacing: 6) {
                        RichBodyView(markdown: text, connection: model.connection, isSelectable: false)
                        if let speakFirstReason { SpeakFirstChoicesView(model: model, reason: speakFirstReason) }
                    }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .modifier(OpensThread(root: threadToOpen(for: id), onOpen: onOpenThread))
                .reactionCorner(isStreaming ? [] : model.transcript.reactions(for: id), currentUserId: model.currentUserId, isLeading: false) { emoji in
                    Task { await model.react(messageId: id, emoji: emoji) }
                }
                }
                .equatable()
                Spacer(minLength: 24)
            }
            threadControl(for: id)
            }
            .frame(maxWidth: Self.bubbleWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let activity):
            if activity.isThinkingHarder {
                ThinkingHarderLine(activity: activity)
            } else {
                ToolGroupRow(tools: [activity])
            }
        case .toolGroup(_, let tools):
            ToolGroupRow(tools: tools)
        case .produced(.artifact(let artifact)):
            ArtifactCardView(artifact: artifact, connection: model.connection) { openArtifact(artifact) }
        case .produced(.file(let file)):
            ProducedFileRow(file: file, connection: model.connection)
        case .question(let card):
            QuestionCardView(card: card, onAnswer: { answer in Task { await model.answer(card, with: answer) } }, onChatInstead: { model.dismissQuestion(card) })
        case .approval(let card):
            ApprovalCardView(card: card) { isApproved in
                Task { await model.decide(card, isApproved: isApproved) }
            }
        case .notice(_, let text, let isError):
            Label(
                text.isEmpty ? (isError ? String(localized: "The assistant could not finish.") : String(localized: "Stopped")) : text,
                systemImage: isError ? "exclamationmark.triangle.fill" : "stop.circle")
                .font(.footnote)
                .foregroundStyle(isError ? AnyShapeStyle(Color.statusError) : AnyShapeStyle(.secondary))
        case .turnEnd(_, let kind, let text, let reason):
            TurnEndLine(kind: kind, text: text, reason: reason).frame(maxWidth: .infinity, alignment: .trailing)
        case .note(_, let note):
            NoteLine(note: note)
        case .goalNeedsYou(_, let goalId, let title, let question):
            GoalNeedsYouCard(goalId: goalId, title: title, question: question)
        }
    }
}

/// OpensThread makes a stored message open its thread when tapped: the one it is a reply in, else its own. Links and buttons inside the
/// message keep working, and a long press still shows its actions.
private struct OpensThread: ViewModifier {
    let root: String?
    let onOpen: ((String) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let root, let onOpen {
            content.onTapGesture { onOpen(root) }
        } else {
            content
        }
    }
}

/// ViewingChip names the screen a message was written about.
private struct ViewingChip: View {
    let viewing: Viewing

    var body: some View {
        Label(viewing.label ?? viewing.id, systemImage: "scope")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.portalCard, in: Capsule())
            .accessibilityLabel(Text("About \(viewing.label ?? viewing.id)"))
    }
}

/// ReactionStrip shows the emoji on a message with how many chose each. It
/// is tapped to take the person's own back or to join in, when `onTap` is given.
struct ReactionStrip: View {
    let reactions: [Reaction]
    let currentUserId: String
    let onTap: ((String) -> Void)?

    var body: some View {
        let summaries = Reactions.summaries(reactions, currentUserId: currentUserId)
        if !summaries.isEmpty {
            HStack(spacing: 6) {
                ForEach(summaries) { summary in
                    let label = HStack(spacing: 3) {
                        Text(summary.emoji)
                        if summary.count > 1 {
                            Text("\(summary.count)").font(.caption)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(summary.isMine ? Color.accentColor.opacity(0.2) : Color.portalCard, in: Capsule())
                    if let onTap {
                        Button { onTap(summary.emoji) } label: { label.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Reacted with \(summary.emoji)"))
                    } else {
                        label.accessibilityLabel(Text("Reacted with \(summary.emoji)"))
                    }
                }
            }
        }
    }
}

/// ToolGroupRow is a stretch of tool calls as one quiet line. With tool
/// details off it opens to the notes the tools wrote; with them on it also
/// shows each call's arguments and result.
private struct ToolGroupRow: View {
    let tools: [ToolActivity]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tools) { tool in
                    ToolLine(tool: tool)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            // No spinner here: the typing dots alone say the turn is at work.
            HStack(spacing: 8) {
                Text("What it did")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if tools.count > 1 {
                    Text("\(tools.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tint(Color.portalSecondary)
        .padding(.vertical, 2)
    }
}

/// ToolLine is one working note. The app never shows a tool's arguments or result: only the plain note, as a customer sees on the web.
private struct ToolLine: View {
    let tool: ToolActivity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(tool.note ?? tool.displayName)
                .font(.footnote)
            Spacer(minLength: 4)
            if let duration = tool.durationText {
                Text(duration)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// ThinkingHarderLine says the quick model handed the turn to the main one.
private struct ThinkingHarderLine: View {
    let activity: ToolActivity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .accessibilityHidden(true)
            Text("Thinking harder")
            if let reason = activity.thinkHarderReason {
                Text(reason).foregroundStyle(.tertiary)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// TurnEndLine says why a turn ended without an answer. It is read from the
/// stored note, so it is still there after a reload.
private struct TurnEndLine: View {
    let kind: TurnEndKind
    let text: String
    let reason: TurnEndReason?

    var body: some View {
        Label {
            if kind == .interruption {
                Text("Stopped")
            } else if kind == .failed {
                Text("Didn\u{2019}t answer. Try again.")
            } else if let reason, let sentence = TurnEndText.sentence(for: reason) {
                Text(sentence)
            } else {
                Text(text)
            }
        } icon: {
            Image(systemName: kind == .failed ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
        }
        .font(.footnote)
        .foregroundStyle(kind == .failed ? AnyShapeStyle(Color.statusError) : AnyShapeStyle(.secondary))
    }
}

/// NoteLine is a small line about the assistant's own turns.
private struct NoteLine: View {
    let note: TranscriptNote

    var body: some View {
        switch note {
        case .backgroundNotice(let text):
            // The only note that is for the person: finished work could not wake the assistant.
            Label(text, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        default:
            // The rest is bookkeeping (a restart, a summary, a schedule, a goal check-in, a depth change,
            // how the conversation began): the messages around it say everything that matters.
            EmptyView()
        }
    }
}

/// BackgroundWorkBanner says work the assistant started is still running.
private struct BackgroundWorkBanner: View {
    let work: BackgroundWork
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TypingDots(dotSize: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Working in the background")
                    .font(.footnote.weight(.semibold))
                Text(work.title ?? work.purpose ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Stop", role: .destructive, action: onStop)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct QuestionCardView: View {
    let card: QuestionCard
    let onAnswer: (String) -> Void
    let onChatInstead: (() -> Void)?
    @State private var chosen: String?
    @State private var otherAnswer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Question", systemImage: "questionmark.bubble")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.question)
                .font(.body)
            // The answers are rows with a radio, not buttons of their own.
            if !card.choices.isEmpty {
                VStack(spacing: 0) {
                    ForEach(card.choices, id: \.self) { choice in
                        Button {
                            chosen = choice
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: chosen == choice ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(chosen == choice ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                                Text(choice).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen == choice ? .isSelected : [])
                        if choice != card.choices.last { Divider() }
                    }
                }
            }
            if onChatInstead != nil {
                if card.allowOther || card.choices.isEmpty {
                    Text("Or type your answer below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if card.allowOther || card.choices.isEmpty {
                // Where the box below is for talking to people, the answer is typed here.
                TextField("Your answer", text: $otherAnswer)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { if !trimmedOther.isEmpty { onAnswer(trimmedOther) } }
            }
            HStack(spacing: 12) {
                if let onChatInstead {
                    Button(action: onChatInstead) {
                        Text("Discuss").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if let chosen { onAnswer(chosen) } else if !trimmedOther.isEmpty { onAnswer(trimmedOther) }
                } label: {
                    Text("Answer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen == nil && trimmedOther.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    private var trimmedOther: String { otherAnswer.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct ApprovalCardView: View {
    let card: ApprovalCard
    let onDecide: (Bool) -> Void
    @State private var isShowingArguments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Approval needed", systemImage: "checkmark.shield")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.statusWarning)
            Text("The assistant wants to use \(card.toolName)")
                .font(.body)
            if !card.arguments.isEmpty {
                DisclosureGroup("Details", isExpanded: $isShowingArguments) {
                    Text(card.arguments.prefix(2000))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(.footnote)
            }
            HStack(spacing: 12) {
                Button {
                    onDecide(true)
                } label: {
                    Text("Do it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    onDecide(false)
                } label: {
                    Text("Don\u{2019}t").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}

private struct ComposerBar: View {
    static func kindName(_ kind: String) -> String {
        switch kind {
        case "site": String(localized: "Site")
        case "controller": String(localized: "Controller")
        case "virtual_controller": String(localized: "Virtual controller")
        case "ticket": String(localized: "Ticket")
        case "incident": String(localized: "Incident")
        case "agent_run": String(localized: "Activity")
        case "cell": String(localized: "Cell")
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let model: ConversationModel
    let voice: VoiceCallController?
    let dictation: DictationController
    let drafts: AttachmentDrafts
    @Binding var draft: String
    /// Starts a call with the assistant, offered as Talk in the composer's [+].
    var onTalk: (() -> Void)?

    private var placeholder: LocalizedStringKey {
        if model.activeQuestion != nil { return LocalizedStringKey("Your answer") }
        return model.isThread ? LocalizedStringKey("Reply in thread") : LocalizedStringKey("Message")
    }

    private var isDraftEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { !isDraftEmpty || !drafts.items.isEmpty }

    /// The microphone button, when the server has dictation set up for this person.
    private var dictationControl: DictationControl? {
        guard session.voiceAvailability.isDictationAvailable else { return nil }
        return DictationControl(isListening: dictation.isListening, isEnabled: dictation.phase != .finishing) { toggleDictation() }
    }

    private func toggleDictation() {
        if appModel.callCenter.isInCall || voice?.isActive == true {
            dictation.report(String(localized: "You cannot dictate during a call."))
            return
        }
        session.readAloud.stop()
        dictation.toggle(place: .agent, connection: model.connection, isDemo: appModel.isDemo) { words in
            draft = DictationText.appending(words, to: draft)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if session.readAloud.isShowingBar { ReadAloudBar(readAloud: session.readAloud) }
            if dictation.isShowingStatus { DictationStatus(dictation: dictation) }
            if let error = model.actionError {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.statusError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if canSend {
                        Button("Retry") { send() }
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(.horizontal, 20)
            }
            if model.replyTarget != nil || model.viewingReference != nil {
                ReferencesBar(reply: model.replyTarget, onCancelReply: { model.replyTarget = nil }) {
                    if let reference = model.viewingReference {
                        ReferenceChip(systemImage: "scope", text: ReferenceHandoff.chipText(kindName: Self.kindName(reference.viewing.kind), subject: reference.subject)) { model.viewingReference = nil }
                    }
                }
                .padding(.horizontal, 12)
            }
            // While a call is on, the conversation's stage shows it and the composer and keyboard stay down.
            if let voice, voice.isActive || voice.phase != .idle {
                EmptyView()
            } else {
            if let attachError = drafts.errorText {
                Text(attachError).font(.footnote).foregroundStyle(Color.statusError).padding(.horizontal, 20)
            }
            ComposerCard(
                placeholder: placeholder, text: $draft, drafts: drafts,
                canSend: canSend,
                onVoice: onTalk,
                onStop: model.isRunning ? { Task { await model.cancelRun() } } : nil, dictation: dictationControl,
                onEscape: {
                    guard draft.isEmpty, model.replyTarget != nil else { return false }
                    model.replyTarget = nil
                    return true
                }, onSend: send)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .onChange(of: voice?.isActive ?? false) { _, isActive in
            // The keyboard goes down when a call starts.
            if isActive { dictation.abort() }
            if isActive { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }

    private func send() {
        // What is still being said belongs to the message that was sent, not to the next one.
        dictation.abort()
        let text = draft
        draft = ""
        Task {
            if await !model.send(text, attachments: drafts) { draft = text }
        }
    }
}

/// GoalNeedsYouCard is a goal that is blocked on the person: its question,
/// and a way into the goal. The person may also answer in the conversation
/// and the assistant passes it on.
private struct GoalNeedsYouCard: View {
    @Environment(SessionModel.self) private var session
    let goalId: String
    let title: String
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("A goal needs you", systemImage: "scope")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.statusWarning)
            Text(title).font(.subheadline.weight(.semibold))
            Text(question).font(.body)
            Text("Answer here and the assistant passes it on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !goalId.isEmpty {
                Button {
                    session.open(.goal(id: goalId))
                } label: {
                    Label("Open the goal", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// SpeakFirstChoicesView offers "Not now" and "Stop these" at the foot of the
/// first answer after the assistant started a conversation, and says what happened.
private struct SpeakFirstChoicesView: View {
    let model: ConversationModel
    let reason: String

    var body: some View {
        if let outcome = model.speakFirstOutcome {
            Label(outcome, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Spacer(minLength: 0)
                Menu {
                    Button("Not now") { Task { await model.snoozeSpeakFirst() } }
                    Button("Stop these") { Task { await model.stopSpeakingFirst(reason: reason) } }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .tint(.secondary)
                // The target stays 44 points; the footer of the message does not grow by it.
                .padding(.vertical, -10)
                .padding(.trailing, -10)
            }
        }
    }
}

/// FilingNoteView says what the assistant remembered from this conversation,
/// with each fact opening its page and a way to forget it.
private struct FilingNoteView: View {
    @Environment(AppModel.self) private var appModel
    let model: ConversationModel
    let filing: MemoryFiling
    @State private var isExpanded = false
    @State private var forgetting: MemoryFact?

    var body: some View {
        let facts = filing.facts ?? []
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.sentence ?? "").font(.footnote)
                        HStack(spacing: 10) {
                            if fact.isInferred == true {
                                Text("Inferred").font(.caption2.weight(.semibold)).foregroundStyle(Color.statusWarning)
                            }
                            if let path = fact.pagePath, let number = fact.number {
                                Button("Open") { appModel.openedCitation = MemoryCitation(path: path, number: number) }
                                    .font(.caption)
                            }
                            Button("Forget", role: .destructive) { forgetting = fact }
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Group {
                if facts.count == 1 {
                    Label("Remembered 1 thing", systemImage: "brain.head.profile")
                } else {
                    Label("Remembered \(facts.count) things", systemImage: "brain.head.profile")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .tint(Color.portalSecondary)
        .confirmationDialog("Forget this?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget it", role: .destructive) {
                if let fact = forgetting { Task { await model.forgetFiledFact(fact, in: filing) } }
            }
        } message: {
            Text("The assistant stops knowing it. This cannot be undone.")
        }
    }
}

/// ArtifactListSheet lists the pages, drawings and documents the assistant
/// made in a conversation; one opens full size.
private struct ArtifactListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conversationId: String
    /// The thread the list is for, which lists what was made in it and what its messages show; nil for the main history.
    var threadRootMessageId: String?
    var cardArtifactIds: Set<String> = []
    let connection: Connection
    let onOpen: (ArtifactReference) -> Void

    @State private var artifacts: [ArtifactReference] = []
    @State private var phase = LoadPhase.loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading: ProgressView()
                case .failed(let message):
                    ContentUnavailableView("Could not load this", systemImage: "wifi.exclamationmark", description: Text(message))
                case .loaded:
                    if artifacts.isEmpty {
                        ContentUnavailableView("Nothing made yet", systemImage: "doc.richtext", description: Text("Pages and charts the assistant makes in this conversation show up here."))
                    } else {
                        List(artifacts) { artifact in
                            Button { onOpen(artifact) } label: {
                                HStack {
                                    Image(systemName: artifact.kind == .markdown ? "doc.text" : artifact.kind == .svg ? "scribble" : "chart.bar.doc.horizontal")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artifact.title.isEmpty ? String(localized: "Untitled") : artifact.title).foregroundStyle(.primary)
                                        if let size = artifact.sizeBytes {
                                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Color.portalCard)
                        }
                        .portalList()
                    }
                }
            }
            .navigationTitle("Pages and files it made")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            do {
                let all = try await connection.conversationArtifacts(conversationId: conversationId)
                artifacts = ThreadViews.artifacts(all, inView: threadRootMessageId, cardIds: cardArtifactIds)
                phase = .loaded
            } catch {
                phase = .failed(error.userMessage)
            }
        }
    }
}
