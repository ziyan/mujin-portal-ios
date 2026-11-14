import PortalKit
import SwiftUI

/// ArchivedConversationsView lists the person's archived conversations and chats, which the chat list and its search leave out.
/// Each can be restored, with a swipe or from its menu, and goes back to the list; a tap opens it.
struct ArchivedConversationsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account
    let connection: Connection
    /// Opens a conversation from the archive.
    let onOpen: (ConversationSummary) -> Void
    /// A conversation went back to the chat list.
    let onRestored: () -> Void
    let onError: @MainActor (Error) -> Void

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @State private var phase = Phase.loading
    @State private var conversations: [ConversationSummary] = []

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not load archived chats", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                case .loaded:
                    if conversations.isEmpty {
                        ContentUnavailableView("No archived chats", systemImage: "archivebox")
                    } else {
                        List {
                            PortalRows {
                                ForEach(conversations) { conversation in
                                    Button {
                                        dismiss()
                                        onOpen(conversation)
                                    } label: {
                                        ConversationRow(conversation: conversation, waitingCount: 0)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button("Restore") { Task { await restore(conversation) } }
                                            .tint(Color.accentColor)
                                    }
                                    .contextMenu {
                                        Button { Task { await restore(conversation) } } label: {
                                            Label("Restore", systemImage: "tray.and.arrow.up")
                                        }
                                    }
                                    .accessibilityAction(named: Text("Restore")) { Task { await restore(conversation) } }
                                }
                            }
                        }
                        .portalRootList()
                        .refreshable { await load() }
                    }
                }
            }
            .navigationTitle("Archived")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            conversations = try await connection.archivedConversations(userId: account.userId)
            phase = .loaded
        } catch {
            onError(error)
            if conversations.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    /// The row leaves at once; it comes back if the server refuses, where it was, and only it: the list may have been read again
    /// in between.
    private func restore(_ conversation: ConversationSummary) async {
        let index = conversations.firstIndex { $0.id == conversation.id }
        conversations.removeAll { $0.id == conversation.id }
        do {
            try await connection.restoreConversation(id: conversation.id)
            onRestored()
        } catch {
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.insert(conversation, at: min(index ?? 0, conversations.count))
            }
            onError(error)
        }
    }
}
