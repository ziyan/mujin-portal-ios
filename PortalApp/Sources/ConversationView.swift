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
    @State private var draft = ""
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var emojiTarget: EmojiTarget?
    @State private var fullArtifact: ArtifactReference?
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
        .fullScreenCover(item: $fullArtifact) { artifact in
            ArtifactFullView(artifact: artifact, connection: appModel.connection(for: account))
        }
        .task(id: conversationId) {
            let conversationModel = ConversationModel(
                conversationId: conversationId, currentUserId: account.userId, connection: appModel.connection(for: account),
                socketFactory: appModel.socketFactory,
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            model = conversationModel
            conversationModel.start()
        }
        .onAppear { model?.start() }
        .onDisappear { model?.stop() }
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
                    ComposerBar(model: model, draft: $draft)
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
                HStack {
                    Spacer(minLength: 48)
                    Text(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(Color.onAccent)
                        .textSelection(.enabled)
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
        case .turnEnd(_, let kind, let text):
            TurnEndLine(kind: kind, text: text)
        case .note(_, let note):
            NoteLine(note: note)
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

    var body: some View {
        Label {
            if kind == .failed {
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
