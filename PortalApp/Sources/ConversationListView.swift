import PortalKit
import SwiftUI

/// ConversationListView is the home screen: the person's conversations,
/// newest first, with a way to start one and to switch accounts.
struct ConversationListView: View {
    @Environment(AppModel.self) private var appModel
    let account: Account

    @State private var model: ConversationListModel?
    @State private var selectedConversationId: String?
    @State private var isShowingAccounts = false

    var body: some View {
        NavigationSplitView {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingAccounts = true
                    } label: {
                        Label("Accounts", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("accountsButton")
                    // A popover on the iPad, anchored to this button; a sheet on the iPhone.
                    .popover(isPresented: $isShowingAccounts) {
                        AccountsView()
                    }
                }
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
            if appModel.isDemo, let screen = ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"], screen.hasPrefix("conversation:") {
                selectedConversationId = String(screen.dropFirst("conversation:".count))
            }
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
                ContentUnavailableView {
                    Label("No conversations yet", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start one to ask your assistant something.")
                } actions: {
                    Button("New conversation") { Task { await startConversation() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(model.conversations, selection: $selectedConversationId) { conversation in
                    NavigationLink(value: conversation.id) {
                        ConversationRow(conversation: conversation)
                    }
                    .swipeActions {
                        Button("Archive", role: .destructive) { Task { await model.archive(conversation) } }
                    }
                }
                .refreshable { await model.load() }
            }
        }
    }

    private func startConversation() async {
        guard let model, let conversationId = await model.createConversation() else { return }
        selectedConversationId = conversationId
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary
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

#Preview("Conversations") {
    let model = DemoServer.makeModel()
    ConversationListView(account: model.activeAccount!)
        .environment(model)
}
