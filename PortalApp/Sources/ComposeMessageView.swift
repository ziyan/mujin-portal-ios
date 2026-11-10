import PortalKit
import SwiftUI

/// ComposeMessageView is the one way to start a conversation: an empty
/// message with a "To" row. Left empty it is a conversation with the
/// assistant. With one person picked the first send starts a direct chat,
/// with two or more a group, and the message goes there.
struct ComposeMessageView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    /// What a screen asked to ask about, or the words waiting in the box.
    var request: SessionModel.ComposeRequest?
    let onSent: (String) -> Void
    /// Told what was started, for a list that shows it before the server is asked: the text sent and whether it is a chat with people.
    var onStarted: ((_ conversationId: String, _ text: String, _ isChat: Bool) -> Void)?
    /// People already chosen, such as the other person of a chat that becomes a group.
    var initialPicked: [ChatCandidate] = []
    /// A conversation with the assistant this one carries a reference to.
    var reference: (id: String, title: String)?
    var note: LocalizedStringKey?

    @State private var picked: [ChatCandidate] = []
    @State private var didStart = false
    @State private var query = ""
    @State private var candidates: [ChatCandidate] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorText: String?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toRow
                Divider()
                if let reference {
                    HStack {
                        Label(reference.title, systemImage: "bubble.left")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                if let subject = request?.subject, picked.isEmpty {
                    HStack {
                        Label(subject, systemImage: "scope")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !query.isEmpty {
                    List(available) { person in
                        Button {
                            picked.append(person)
                            query = ""
                        } label: {
                            CandidateRow(person: person, showsOrganization: true, isSelected: nil)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.portalCard)
                    }
                    .portalList()
                } else {
                    Spacer()
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Color.statusError).padding(.horizontal, 20)
                    }
                }
                ComposerCard(
                    placeholder: picked.isEmpty ? LocalizedStringKey("Ask the assistant") : LocalizedStringKey("Message"), text: $draft,
                    canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending, isSending: isSending,
                    fieldIdentifier: "composeField", sendIdentifier: "composeSendButton", onSend: { Task { await send() } })
            }
            .background(Color.portalPage)
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if !didStart {
                    picked = initialPicked
                    draft = request?.draft ?? ""
                    didStart = true
                }
            }
            .task(id: query) {
                guard session.capabilities.offersChats, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                    candidates = []
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                candidates = (try? await appModel.connection(for: session.account).chatCandidates(search: query.trimmingCharacters(in: .whitespaces))) ?? []
            }
        }
        .presentationDetents([.large])
    }

    private var available: [ChatCandidate] {
        candidates.filter { candidate in !picked.contains { $0.userId == candidate.userId } }
    }

    /// "To": the people picked as chips, then a field. Empty means the assistant.
    private var toRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("To").foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(picked, id: \.userId) { person in
                        Button {
                            picked.removeAll { $0.userId == person.userId }
                        } label: {
                            HStack(spacing: 4) {
                                Text(person.shownName)
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(person.shownName)"))
                    }
                    TextField(picked.isEmpty ? LocalizedStringKey("The assistant") : LocalizedStringKey("Add someone"), text: $query)
                        .focused($isQueryFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minWidth: 140, minHeight: 44)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func send() async {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // The context travels as a link to the conversation, which shows as a card in the chat.
        if let reference, !picked.isEmpty { text += "\n\n" + PortalLink.conversation(id: reference.id).url(server: session.account.server).absoluteString }
        isSending = true
        defer { isSending = false }
        let connection = appModel.connection(for: session.account)
        do {
            let name = picked.map { $0.shownName.split(separator: " ").first.map(String.init) ?? $0.shownName }.joined(separator: ", ")
            // Nothing exists until now: the conversation is made with its first message.
            let conversationId = try await connection.startConversation(
                withPeople: picked.map(\.userId), groupName: name, text: text, viewing: picked.isEmpty ? request?.viewing.map { Viewing(kind: $0.kind, id: $0.id, label: request?.subject) } : nil)
            dismiss()
            onStarted?(conversationId, text, !picked.isEmpty)
            onSent(conversationId)
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}
