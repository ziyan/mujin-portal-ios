import PortalKit
import SwiftUI

/// ConversationListView is the Assistant tab: what waits for the person,
/// then their conversations, newest first, with search and a way to start one.
struct ConversationListView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var model: ConversationListModel?
    @State private var selectedConversationId: String?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Assistant")
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startConversation() }
                    } label: {
                        Label("New conversation", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("newConversationButton")
                }
            }
        } detail: {
            if let selectedConversationId {
                NavigationStack {
                    ConversationView(
                        account: account, conversationId: selectedConversationId,
                        title: model?.conversations.first { $0.id == selectedConversationId }?.title)
                }
                .id(selectedConversationId)
            } else {
                ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .task(id: account.accountKey) {
            let listModel = ConversationListModel(
                account: account, connection: appModel.connection(for: account),
                onError: { [appModel, account] error in appModel.handle(error, account: account) })
            model = listModel
            await listModel.load()
            if appModel.isDemo, let screen = DemoOptions.screen, screen.hasPrefix("conversation:") {
                selectedConversationId = String(screen.dropFirst("conversation:".count))
            }
        }
        .task(id: searchText) {
            // Search waits for a pause in typing.
            if !searchText.isEmpty { try? await Task.sleep(nanoseconds: 300_000_000) }
            if Task.isCancelled { return }
            await model?.search(searchText)
        }
        .onChange(of: session.conversationToOpen, initial: true) { _, conversationId in
            guard let conversationId else { return }
            selectedConversationId = conversationId
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
            if model.conversations.isEmpty && session.waiting.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No conversations yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start one to ask your assistant something.")
                    } actions: {
                        Button("New conversation") { Task { await startConversation() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else {
                List(selection: $selectedConversationId) {
                    if !session.waiting.isEmpty, model.searchText.isEmpty {
                        Section("Waiting for you") {
                            ForEach(session.waiting) { item in
                                WaitingRow(item: item) { selectedConversationId = item.conversationId }
                            }
                        }
                    }
                    Section {
                        ForEach(model.conversations) { conversation in
                            NavigationLink(value: conversation.id) {
                                ConversationRow(conversation: conversation, waitingCount: session.waitingCounts[conversation.id] ?? 0)
                            }
                            .swipeActions {
                                Button("Archive", role: .destructive) { Task { await model.archive(conversation) } }
                            }
                        }
                    }
                }
                .refreshable {
                    await model.load()
                    await session.refreshWaiting()
                }
            }
        }
    }

    private func startConversation() async {
        guard let model, let conversationId = await model.createConversation() else { return }
        selectedConversationId = conversationId
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
                        item.isApproval ? "Approval needed" : "Question",
                        systemImage: item.isApproval ? "checkmark.shield" : "questionmark.bubble"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(item.isApproval ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
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
                Text(errorText).font(.footnote).foregroundStyle(.red)
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
        // At the accessibility sizes the date goes under the title instead of
        // beside it, which would leave the title no room in a narrow sidebar.
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title?.isEmpty == false ? conversation.title! : String(localized: "New conversation"))
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                if let summary = conversation.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                if let date = conversation.lastActivity {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if waitingCount > 0 {
                    Label("\(waitingCount)", systemImage: "exclamationmark.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("Waiting for you"))
                }
                if conversation.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Working")
                }
            }
        }
        .padding(.vertical, 2)
    }
}
