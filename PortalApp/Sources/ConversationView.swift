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
        .navigationTitle(shownTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameDraft = shownTitle
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
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
        .task(id: conversationId) {
            let conversationModel = ConversationModel(
                conversationId: conversationId, currentUserId: account.userId, connection: appModel.connection(for: account),
                socketFactory: appModel.socketFactory,
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            if let pending = session.pendingReference, pending.conversationId == conversationId {
                conversationModel.viewingReference = (pending.viewing, pending.subject)
                session.pendingReference = nil
            }
            if let draftToStart = session.pendingDraft, draftToStart.conversationId == conversationId {
                draft = draftToStart.text
                session.pendingDraft = nil
            }
            model = conversationModel
            voice?.end()
            voice = VoiceCallController(
                model: conversationModel, connection: appModel.connection(for: account), socketFactory: URLSessionVoiceSocket.factory)
            conversationModel.start()
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
        if let modelTitle = model?.title, !modelTitle.isEmpty { return modelTitle }
        if let title, !title.isEmpty { return title }
        return String(localized: "New conversation")
    }

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
                    ComposerBar(model: model, voice: voice, draft: $draft)
                }
        }
    }

    private func transcript(_ model: ConversationModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.window.earlierCount > 0 {
                        Button {
                            Task { await model.loadEarlier() }
                        } label: {
                            Text("\(model.window.earlierCount) earlier messages")
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoadingEarlier)
                    }
                    if model.transcript.entries.isEmpty {
                        ContentUnavailableView {
                            Label("Ask anything", systemImage: "sparkles")
                        } description: {
                            Text("Your assistant can look things up and take actions with your approval.")
                        }
                        .padding(.top, 48)
                    }
                    ForEach(model.transcript.displayEntries) { entry in
                        TranscriptRow(
                            entry: entry, model: model, showsToolDetails: showsToolDetails,
                            openArtifact: { fullArtifact = $0 }, moreEmoji: { emojiTarget = EmojiTarget(id: $0) }
                        )
                        .id(entry.id)
                    }
                    if model.isRunning, !model.transcript.entries.contains(where: Self.isStreamingOrCard) {
                        ProgressView()
                            .padding(.leading, 4)
                            .accessibilityLabel("Working")
                    }
                    if let note = model.filingNote {
                        FilingNoteView(model: model, filing: note)
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
            .defaultScrollAnchor(.bottom)
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

    private static func isStreamingOrCard(_ entry: TranscriptEntry) -> Bool {
        switch entry {
        case .assistant(_, _, let isStreaming): isStreaming
        case .question, .approval: true
        default: false
        }
    }
}

private struct TranscriptRow: View {
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
                    Text(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(Color.onAccent)
                        .textSelection(.enabled)
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
                // The assistant's first reaction to a typed message lands here. It is shown, not tapped.
                ReactionStrip(reactions: model.transcript.reactions(for: id), currentUserId: model.currentUserId, onTap: nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant(let id, let text, let isStreaming):
            VStack(alignment: .leading, spacing: 6) {
                MarkdownView(markdown: text)
                if !isStreaming {
                    ReactionStrip(reactions: model.transcript.reactions(for: id), currentUserId: model.currentUserId) { emoji in
                        Task { await model.react(messageId: id, emoji: emoji) }
                    }
                }
            }
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
                        Button { onTap(summary.emoji) } label: { label }
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if tools.count > 1 {
                    Text("\(tools.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tint(Color.portalSecondary)
        .padding(10)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            if let reason, reason.kind != "failed", let sentence = TurnEndText.sentence(for: reason) {
                Text(sentence)
            } else if kind == .failed {
                if text.isEmpty {
                    Text("This answer failed.")
                } else {
                    Text("This answer failed: \(text)")
                }
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
    @State private var isExpanded = false

    var body: some View {
        switch note {
        case .restart:
            Label("Carrying on after a restart", systemImage: "arrow.counterclockwise")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .scheduled(let jobName, let message):
            openable(Label("Scheduled: \(jobName)", systemImage: "clock"), body: message)
        case .backgroundFinished(let title, let report):
            openable(Label("Background work finished: \(title)", systemImage: "checkmark.circle"), body: report)
        case .backgroundNotice(let text):
            Label(text, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .compaction(let summary):
            openable(Label("Earlier messages were summarized", systemImage: "arrow.down.right.and.arrow.up.left"), body: summary)
        case .speakFirst(let reason):
            Label("The assistant started this conversation (\(TurnEndText.speakFirstReason(reason)))", systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .goalCheckIn(let title, let message):
            openable(Label("Goal check-in: \(title)", systemImage: "scope"), body: message)
        case .depth(let kind, let reason, let sentence):
            HStack(spacing: 6) {
                Image(systemName: kind == .thinkingHarder ? "brain" : "magnifyingglass")
                    .accessibilityHidden(true)
                Text(kind == .thinkingHarder ? "Thinking harder" : "Looking more closely")
                if !reason.isEmpty {
                    Text(reason).foregroundStyle(.tertiary)
                } else if !sentence.isEmpty {
                    Text(sentence).foregroundStyle(.tertiary)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func openable(_ label: some View, body text: String) -> some View {
        if text.isEmpty {
            label.font(.footnote).foregroundStyle(.secondary)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                MarkdownView(markdown: text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } label: {
                label.font(.footnote).foregroundStyle(.secondary)
            }
            .tint(Color.portalSecondary)
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
    @State private var otherAnswer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Question", systemImage: "questionmark.bubble")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.question)
                .font(.body)
            ForEach(card.choices, id: \.self) { choice in
                Button {
                    onAnswer(choice)
                } label: {
                    Text(choice).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            if card.allowOther || card.choices.isEmpty {
                HStack {
                    TextField("Your answer", text: $otherAnswer)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit(submitOther)
                    Button("Send", action: submitOther)
                        .buttonStyle(.borderedProminent)
                        .disabled(otherAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let onChatInstead {
                Button(action: onChatInstead) {
                    Label("Chat about it instead", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func submitOther() {
        let answer = otherAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        onAnswer(answer)
    }
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
            if !card.policyReason.isEmpty {
                Text(card.policyReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !card.risk.isEmpty {
                Text("Risk: \(card.risk)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                    onDecide(false)
                } label: {
                    Text("Reject").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    onDecide(true)
                } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ComposerBar: View {
    let model: ConversationModel
    let voice: VoiceCallController?
    @Binding var draft: String
    @FocusState private var isFocused: Bool

    private var isDraftEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
            if let voice, voice.isActive || voice.phase != .idle {
                VoiceCallBar(voice: voice)
                    .padding(.horizontal, 12)
            }
            if model.activeQuestion != nil {
                Label("Your message answers the question above.", systemImage: "questionmark.bubble")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            GlassEffectContainer {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(model.activeQuestion == nil ? LocalizedStringKey("Message") : LocalizedStringKey("Your answer"), text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($isFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .accessibilityIdentifier("messageField")
                        // With a hardware keyboard, Escape in an empty field takes the reply away.
                        .onKeyPress(.escape, phases: .down) { _ in
                            guard draft.isEmpty, model.replyTarget != nil else { return .ignored }
                            model.replyTarget = nil
                            return .handled
                        }
                        // With a hardware keyboard, Return sends and Shift+Return
                        // adds a line. The on-screen keyboard is not affected.
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            guard !isDraftEmpty else { return .handled }
                            send()
                            return .handled
                        }
                    // Stop and Send are both there while a turn runs: a message sent
                    // meanwhile steers the turn.
                    if model.isRunning {
                        Button {
                            Task { await model.cancelRun() }
                        } label: {
                            Image(systemName: "stop.fill")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Stop")
                    }
                    if isDraftEmpty, let voice, !voice.isActive {
                        Button {
                            Task { await voice.start() }
                        } label: {
                            Image(systemName: "waveform")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Talk to the assistant")
                        .accessibilityIdentifier("voiceButton")
                    }
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(isDraftEmpty)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("sendButton")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: ConversationView.readableWidth + 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            if await !model.send(text) { draft = text }
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
            HStack(spacing: 10) {
                Button("Not now") { Task { await model.snoozeSpeakFirst() } }
                Button("Stop these") { Task { await model.stopSpeakingFirst(reason: reason) } }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// VoiceCallBar is the call in progress: what is heard, whether the answer is
/// being read, and the buttons to mute and end it.
private struct VoiceCallBar: View {
    let voice: VoiceCallController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .symbolEffect(.variableColor.iterative, isActive: voice.phase == .listening && !voice.isMuted)
                .foregroundStyle(voice.isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                if !voice.caption.isEmpty {
                    Text(voice.caption).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                } else if let notice = voice.notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                } else if voice.isUsingOlderPath, voice.isActive {
                    Text("Speak, then pause. Talking over the answer is not available on this server.")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if voice.isActive {
                Button {
                    voice.toggleMute()
                } label: {
                    Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(voice.isMuted ? "Unmute" : "Mute")
            }
            Button {
                voice.end()
            } label: {
                Image(systemName: voice.isActive ? "phone.down.fill" : "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(voice.isActive ? Color.statusError : nil)
            .accessibilityLabel(voice.isActive ? "End the call" : "Close")
        }
        .padding(12)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch voice.phase {
        case .speaking: "speaker.wave.2.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "waveform"
        }
    }

    private var status: LocalizedStringKey {
        switch voice.phase {
        case .idle: ""
        case .connecting: "Connecting…"
        case .listening: voice.isMuted ? "Muted" : "Listening"
        case .speaking: "Speaking"
        case .failed(let message): LocalizedStringKey(message)
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
