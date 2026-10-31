import PortalKit
import SwiftUI

/// AskAboutRequest names a screen's resource for a question to the assistant.
struct AskAboutRequest: Identifiable {
    let id = UUID()
    let viewing: Viewing
    /// What the person sees as the subject, such as a ticket's number and title.
    let subject: String
}

extension View {
    /// Presents the "Ask about this" sheet for a request a screen sets.
    func askAboutSheet(item: Binding<AskAboutRequest?>) -> some View {
        sheet(item: item) { request in
            AskAboutSheet(request: request)
        }
    }
}

/// AskAboutButton is the toolbar action that starts a question about the screen.
struct AskAboutButton: View {
    @Binding var request: AskAboutRequest?
    let viewing: Viewing
    let subject: String

    var body: some View {
        Button {
            request = AskAboutRequest(viewing: viewing, subject: subject)
        } label: {
            Label("Ask about this", systemImage: "sparkles")
        }
    }
}

/// AskAboutSheet takes a question, sends it with the resource it is about to a
/// new conversation, and opens that conversation in the Assistant tab.
struct AskAboutSheet: View {
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let request: AskAboutRequest

    @State private var question = ""
    @State private var errorText: String?
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form { PortalRows {
                Section {
                    Label(request.subject, systemImage: "scope")
                        .foregroundStyle(.primary)
                }
                Section("Your question") {
                    TextField("What do you want to know?", text: $question, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Color.statusError) }
                }
            } }
.portalList()
            .navigationTitle("Ask about this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ask") { Task { await send() } }
                        .disabled(isSending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        errorText = await session.ask(about: request.viewing, question: question.trimmingCharacters(in: .whitespacesAndNewlines))
        if errorText == nil { dismiss() }
    }
}
