import PortalKit
import SwiftUI

/// ConversationView is one conversation: the transcript with the answer
/// streaming in, question and approval cards, and the composer.
struct ConversationView: View {
    @Environment(AppModel.self) private var appModel
    let account: Account
    let conversationId: String
    let title: String?

    @State private var model: ConversationModel?
    @State private var draft = ""

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.title?.isEmpty == false ? model!.title! : (title?.isEmpty == false ? title! : String(localized: "New conversation")))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: conversationId) {
            let conversationModel = ConversationModel(
                conversationId: conversationId, connection: appModel.connection(for: account), socketFactory: appModel.socketFactory,
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            model = conversationModel
            conversationModel.start()
        }
        .onAppear { model?.start() }
        .onDisappear { model?.stop() }
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
                    if model.transcript.entries.isEmpty {
                        ContentUnavailableView {
                            Label("Ask anything", systemImage: "sparkles")
                        } description: {
                            Text("Your assistant can look things up and take actions with your approval.")
                        }
                        .padding(.top, 48)
                    }
                    ForEach(model.transcript.entries) { entry in
                        TranscriptRow(entry: entry, model: model)
                            .id(entry.id)
                    }
                    if model.isRunning, !model.transcript.entries.contains(where: Self.isStreamingOrCard) {
                        ProgressView()
                            .padding(.leading, 4)
                            .accessibilityLabel("Working")
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

    var body: some View {
        switch entry {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
        case .assistant(_, let text, _):
            MarkdownView(markdown: text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(_, let name, let arguments, let result):
            ToolRow(name: name, arguments: arguments, result: result)
        case .question(let card):
            QuestionCardView(card: card) { answer in
                Task { await model.answer(card, with: answer) }
            }
        case .approval(let card):
            ApprovalCardView(card: card) { isApproved in
                Task { await model.decide(card, isApproved: isApproved) }
            }
        case .notice(_, let text, let isError):
            Label(
                text.isEmpty ? (isError ? String(localized: "The assistant could not finish.") : String(localized: "Stopped")) : text,
                systemImage: isError ? "exclamationmark.triangle.fill" : "stop.circle")
                .font(.footnote)
                .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
    }
}

private struct ToolRow: View {
    let name: String
    let arguments: String
    let result: String?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !arguments.isEmpty {
                    Text(arguments)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let result, !result.isEmpty {
                    Divider()
                    Text(result.prefix(2000))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                if result == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(name.isEmpty ? String(localized: "Tool") : name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuestionCardView: View {
    let card: QuestionCard
    let onAnswer: (String) -> Void
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
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func submitOther() {
        let answer = otherAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        onAnswer(answer)
    }
}

private struct ApprovalCardView: View {
    let card: ApprovalCard
    let onDecide: (Bool) -> Void
    @State private var isShowingArguments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Approval needed", systemImage: "checkmark.shield")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct ComposerBar: View {
    let model: ConversationModel
    @Binding var draft: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            if let error = model.actionError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            GlassEffectContainer {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
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
                            guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.isRunning else { return .handled }
                            send()
                            return .handled
                        }
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
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "arrow.up")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send")
                        .accessibilityIdentifier("sendButton")
                    }
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
