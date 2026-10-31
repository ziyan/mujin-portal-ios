import PortalKit
import SwiftUI

/// ConversationView is one conversation: the transcript with the answer
/// streaming in, question and approval cards, and the composer.
struct ConversationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account
    let conversationId: String
    let title: String?

    @State private var model: ConversationModel?
    @State private var voice: VoiceCallController?
    @State private var draft = ""
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var emojiTarget: EmojiTarget?
    @State private var fullArtifact: ArtifactReference?
    @State private var isShowingArtifacts = false
    @State private var isAddingPeople = false
    @State private var drafts = AttachmentDrafts()
    @AppStorage("toolDetailsSetting") private var toolDetailsSetting = ""

    struct EmojiTarget: Identifiable {
        let id: String
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .conversationBar(title: shownTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isAddingPeople = true
                    } label: {
                        Label("Add people", systemImage: "person.badge.plus")
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
                    if let model, model.memorySetting?.isFilingActive != false {
                        Button {
                            Task { await model.rememberNow() }
                        } label: {
                            Label("Remember this now", systemImage: "brain.head.profile")
                        }
                        .disabled(model.isRemembering)
                    }
                } label: {
                    Label("Conversation options", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename conversation", isPresented: $isRenaming) {
            TextField("Title", text: $renameDraft)
            Button("Save") { Task { await model?.rename(to: renameDraft) } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $emojiTarget) { target in
            EmojiEntryView { emoji in
                Task { await model?.react(messageId: target.id, emoji: emoji) }
            }
        }
        .attachmentPickers(drafts)
        .sheet(isPresented: $isAddingPeople) {
            ComposeMessageView(onSent: { session.open(.chat(conversationId: $0)) }, reference: (conversationId, shownTitle))
        }
        .sheet(isPresented: $isShowingArtifacts) {
            ArtifactListSheet(conversationId: conversationId, connection: appModel.connection(for: account)) { artifact in
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
        .onChange(of: session.pendingReference?.conversationId) { _, id in
            // The main chat may already be open when an Ask button is tapped.
            guard id == conversationId, let pending = session.pendingReference, let model else { return }
            model.viewingReference = (pending.viewing, pending.subject)
            session.pendingReference = nil
        }
        .task(id: conversationId) {
            let conversationModel = ConversationModel(
                conversationId: conversationId, currentUserId: account.userId, connection: appModel.connection(for: account),
                socketFactory: appModel.socketFactory,
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            if let pending = session.pendingReference, pending.conversationId == conversationId {
                conversationModel.viewingReference = (pending.viewing, pending.subject)
                session.pendingReference = nil
            }
            model = conversationModel
            voice?.end()
            voice = VoiceCallController(
                model: conversationModel, connection: appModel.connection(for: account), socketFactory: URLSessionVoiceSocket.factory)
            conversationModel.start()
            if appModel.isDemo, DemoOptions.screen == "voice" { voice?.startDemo() }
            if appModel.isDemo, DemoOptions.screen == "conversation-reply" {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                conversationModel.replyTarget = ReplyReference(
                    messageId: "m02", authorName: "Assistant", excerpt: "Here is the summary for this week. Three sites are healthy, one needs attention.")
            }
        }
        .onAppear { model?.start() }
        .onDisappear {
            model?.stop()
            voice?.end()
        }
    }

    private var shownTitle: String {
        if isMainChat { return String(localized: "Main chat") }
        if let modelTitle = model?.title, !modelTitle.isEmpty { return modelTitle }
        if let title, !title.isEmpty { return title }
        return String(localized: "New conversation")
    }

    /// The main chat is named by the app, in the person's language, and cannot be renamed.
    private var isMainChat: Bool { model?.isMain == true || session.knownMainConversationId == conversationId }

    private var showsToolDetails: Bool {
        AssistantDisplay.showsToolDetails(setting: toolDetailsSetting, persona: session.persona)
    }

    @ViewBuilder
    private func content(_ model: ConversationModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load this conversation", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.reload() } }
            }
        case .loaded:
            transcript(model)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerBar(model: model, voice: voice, drafts: drafts, draft: $draft)
                }
        }
    }

    private func transcript(_ model: ConversationModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Earlier messages load as the top comes into view; no strip says so.
                    if model.window.earlierCount > 0 {
                        Color.clear.frame(height: 1)
                            .onAppear { Task { await model.loadEarlier() } }
                    }
                    if model.transcript.entries.isEmpty {
                        ContentUnavailableView {
                            Label("Ask anything", systemImage: "sparkles")
                        } description: {
                            Text("Your assistant can look things up and take actions with your approval.")
                        }
                        .padding(.top, 48)
                    }
                    ForEach(model.transcript.displayEntries.filter(Self.isShown)) { entry in
                        TranscriptRow(
                            entry: entry, model: model, showsToolDetails: showsToolDetails,
                            openArtifact: { fullArtifact = $0 }, moreEmoji: { emojiTarget = EmojiTarget(id: $0) }
                        )
                        .id(entry.id)
                    }
                    // From the send until the first words or a tool row: typing dots in the assistant's bubble.
                    if model.isRunning, model.isAwaitingFirstWords {
                        TypingBubble().id("typing")
                    }
                    ForEach(model.backgroundWork) { work in
                        BackgroundWorkBanner(work: work) { Task { await model.stopBackgroundWork(work) } }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Readable width: the column stops growing on wide screens.
                .frame(maxWidth: Self.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.portalPage)
            // A short thread starts at the top; a long one opens, and follows, at the end.
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onChange(of: model.transcript.entries) { _, _ in
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
                        .accessibilityIdentifier("reconnecting")
                }
            }
        }
    }

    static let readableWidth: CGFloat = 720

    /// Bookkeeping notes are not drawn, so they leave no gap either.
    private static func isShown(_ entry: TranscriptEntry) -> Bool {
        if case .note(_, let note) = entry, case .backgroundNotice = note { return true }
        if case .note = entry { return false }
        return true
    }

    private static func isStreamingOrCard(_ entry: TranscriptEntry) -> Bool {
        switch entry {
        case .assistant(_, _, let isStreaming): isStreaming
        case .question, .approval: true
        default: false
        }
    }
}

private struct TranscriptRow: View {
    /// Bubbles stop growing here, so a wide iPad window keeps readable lines.
    static let bubbleWidth: CGFloat = 620
    let entry: TranscriptEntry
    let model: ConversationModel
    let showsToolDetails: Bool
    let openArtifact: (ArtifactReference) -> Void
    let moreEmoji: (String) -> Void

    var body: some View {
        switch entry {
        case .user(let id, let text, let viewing):
            VStack(alignment: .trailing, spacing: 4) {
                if let quote = model.transcript.replyQuote(for: id) {
                    SentQuote(authorName: quote.authorName, excerpt: quote.excerpt)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack {
                    Spacer(minLength: 48)
                    // The person's side in the accent's tint with primary text, as in Messages.
                    Text(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .textSelection(.enabled)
                        .reactionCorner(model.transcript.reactions(for: id), currentUserId: model.currentUserId, isLeading: false, onTap: nil)
                        .contextMenu {
                            if !id.hasPrefix("pending:") {
                                Button {
                                    model.replyTarget = ReplyReference(messageId: id, authorName: "", excerpt: text, isOwn: true)
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }
                            }
                        }
                }
                if let viewing {
                    ViewingChip(viewing: viewing)
                }
            }
            .frame(maxWidth: Self.bubbleWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant(let id, let text, let isStreaming):
            HStack {
                MarkdownView(markdown: text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .reactionCorner(isStreaming ? [] : model.transcript.reactions(for: id), currentUserId: model.currentUserId, isLeading: false) { emoji in
                        Task { await model.react(messageId: id, emoji: emoji) }
                    }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: Self.bubbleWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                if !isStreaming {
                    Button {
                        model.replyTarget = ReplyReference(messageId: id, authorName: String(localized: "Assistant"), excerpt: text)
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                    ForEach(Reactions.palette, id: \.self) { emoji in
                        Button(emoji) { Task { await model.react(messageId: id, emoji: emoji) } }
                    }
                    Button {
                        moreEmoji(id)
                    } label: {
                        Label("More emoji", systemImage: "face.smiling")
                    }
                }
            }
        case .tool(let activity):
            if activity.isThinkingHarder {
                ThinkingHarderLine(activity: activity)
            } else {
                ToolGroupRow(tools: [activity], showsDetails: showsToolDetails)
            }
        case .toolGroup(_, let tools):
            ToolGroupRow(tools: tools, showsDetails: showsToolDetails)
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
            TurnEndLine(kind: kind, text: text, reason: reason)
        case .note(_, let note):
            NoteLine(note: note)
        case .goalNeedsYou(_, let goalId, let title, let question):
            GoalNeedsYouCard(goalId: goalId, title: title, question: question)
        case .speakFirstChoices(_, let reason):
            if model.isOwnConversation { SpeakFirstChoicesView(model: model, reason: reason) }
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

/// EmojiEntryView takes any emoji from the system keyboard.
struct EmojiEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let onChoose: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form { PortalRows {
                Section {
                    TextField("Type an emoji", text: $text)
                        .focused($isFocused)
                        .font(.largeTitle)
                } footer: {
                    Text("Use the emoji keyboard. One or two emoji.")
                }
            } }
.portalList()
            .navigationTitle("More emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("React") {
                        onChoose(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!Reactions.isAcceptable(text))
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}

/// ToolGroupRow is a stretch of tool calls as one quiet line. With tool
/// details off it opens to the notes the tools wrote; with them on it also
/// shows each call's arguments and result.
private struct ToolGroupRow: View {
    let tools: [ToolActivity]
    let showsDetails: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tools) { tool in
                    ToolLine(tool: tool, showsDetails: showsDetails)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                if tools.contains(where: \.isRunning) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
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

private struct ToolLine: View {
    let tool: ToolActivity
    let showsDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(showsDetails ? tool.displayName : (tool.note ?? tool.displayName))
                    .font(.footnote)
                if showsDetails, let note = tool.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let duration = tool.durationText {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if showsDetails {
                if !tool.arguments.isEmpty {
                    Text(tool.arguments.prefix(1_000))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let result = tool.result, !result.isEmpty {
                    Text(result.prefix(2_000))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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
            ProgressView().controlSize(.small)
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
    let model: ConversationModel
    let voice: VoiceCallController?
    let drafts: AttachmentDrafts
    @Binding var draft: String

    private var isDraftEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { !isDraftEmpty || !drafts.items.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            if let error = model.actionError {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.statusError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isDraftEmpty {
                        Button("Retry") { send() }
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(.horizontal, 20)
            }
            if model.replyTarget != nil || model.viewingReference != nil {
                ReferencesBar(reply: model.replyTarget, onCancelReply: { model.replyTarget = nil }) {
                    if let reference = model.viewingReference {
                        ReferenceChip(systemImage: "scope", text: reference.subject) { model.viewingReference = nil }
                    }
                }
                .padding(.horizontal, 12)
            }
            // While a call is on, its bar takes the composer's place and the keyboard stays down.
            if let voice, voice.isActive || voice.phase != .idle {
                VoiceCallBar(voice: voice, isThinking: model.isRunning)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
            AttachmentStrip(drafts: drafts)
                .padding(.horizontal, 16)
            if let attachError = drafts.errorText {
                Text(attachError).font(.footnote).foregroundStyle(Color.statusError).padding(.horizontal, 20)
            }
            ComposerCard(
                placeholder: model.activeQuestion == nil ? LocalizedStringKey("Message") : LocalizedStringKey("Your answer"), text: $draft, drafts: drafts,
                canSend: canSend, onVoice: voice.map { voice in { Task { await voice.start() } } },
                onStop: model.isRunning ? { Task { await model.cancelRun() } } : nil,
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
            if isActive { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }

    private func send() {
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

/// SpeakFirstChoicesView offers "Not now" and "Stop these" under the first
/// answer after the assistant started a conversation, and says what happened.
private struct SpeakFirstChoicesView: View {
    let model: ConversationModel
    let reason: String

    var body: some View {
        if let outcome = model.speakFirstOutcome {
            Label(outcome, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Menu {
                Button("Not now") { Task { await model.snoozeSpeakFirst() } }
                Button("Stop these") { Task { await model.stopSpeakingFirst(reason: reason) } }
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
    }
}

/// VoiceCallBar is the call in progress: what is heard, whether the answer is
/// being read, and the buttons to mute and end it.
private struct VoiceCallBar: View {
    let voice: VoiceCallController
    let isThinking: Bool

    var body: some View {
        HStack(spacing: 12) {
            levelMeter
            Text(state)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if voice.isActive {
                Button {
                    voice.toggleMute()
                } label: {
                    Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(voice.isMuted ? Color.white : Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(voice.isMuted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voice.isMuted ? "Unmute" : "Mute")
            }
            Button {
                voice.end()
            } label: {
                Image(systemName: voice.isActive ? "phone.down.fill" : "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(voice.isActive ? Color.statusError : Color.secondary, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.isActive ? "End the call" : "Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.portalCard.opacity(0.92), in: .rect(cornerRadius: 30, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .contain)
        .sensoryFeedback(trigger: voice.phase) { _, new in new == .listening ? .impact(weight: .light) : nil }
    }

    /// How loud the microphone is; a tap cuts a playing answer short where that is possible, and does nothing otherwise.
    private var levelMeter: some View {
        Button {
            voice.cutAnswer()
        } label: {
            ZStack {
                Circle().fill(Color(.tertiarySystemFill))
                Circle()
                    .fill(Color.accentColor.opacity(0.35))
                    .scaleEffect(voice.isMuted ? 0.3 : 0.35 + 0.65 * CGFloat(voice.inputLevel))
                    .animation(.easeOut(duration: 0.1), value: voice.inputLevel)
                Image(systemName: voice.phase == .speaking ? "speaker.wave.2.fill" : "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(voice.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!voice.canCutIn)
        .accessibilityLabel(voice.canCutIn ? Text("Stop the answer") : Text(state))
    }

    /// Only the state, or a problem.
    private var state: LocalizedStringKey {
        switch voice.phase {
        case .idle: ""
        case .connecting: "Connecting\u{2026}"
        case .failed(let message): LocalizedStringKey(message)
        case .speaking: "Speaking"
        case .listening:
            if let notice = voice.notice { LocalizedStringKey(notice) }
            else if voice.isMuted { "Muted" }
            else if isThinking { "Thinking" }
            else { "Listening" }
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
                artifacts = try await connection.conversationArtifacts(conversationId: conversationId)
                phase = .loaded
            } catch {
                phase = .failed(error.userMessage)
            }
        }
    }
}
