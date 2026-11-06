import Observation
import PortalKit
import SwiftUI

/// MyFeedbackModel loads the feedback about Portal the person sent, as the tickets it opened.
@MainActor
@Observable
final class MyFeedbackModel {
    let connection: Connection
    let userId: String
    let onError: @MainActor (Error) -> Void
    private(set) var phase = LoadPhase.loading
    private(set) var tickets: [Ticket] = []

    init(connection: Connection, userId: String, onError: @escaping @MainActor (Error) -> Void) {
        self.connection = connection
        self.userId = userId
        self.onError = onError
    }

    func load() async {
        do {
            tickets = try await connection.portalFeedback(requesterUserId: userId)
            phase = .loaded
        } catch {
            onError(error)
            if tickets.isEmpty { phase = .failed(error.userMessage) }
        }
    }
}

/// MyFeedbackView is how far the feedback the person sent has come: each row shows their words, where the ticket stands and when it
/// was sent, and opens the ticket.
struct MyFeedbackView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session

    @State private var model: MyFeedbackModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("My feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let feedbackModel = model ?? MyFeedbackModel(
                connection: appModel.connection(for: session.account), userId: session.userId,
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            model = feedbackModel
            await feedbackModel.load()
        }
    }

    @ViewBuilder
    private func content(_ model: MyFeedbackModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load your feedback", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            if model.tickets.isEmpty {
                ContentUnavailableView {
                    Label("No feedback yet", systemImage: "text.bubble")
                } description: {
                    Text("Feedback you send about Portal shows here, with how far it has come.")
                }
            } else {
                List(model.tickets) { ticket in
                    NavigationLink(value: PortalRoute.ticket(id: ticket.id)) {
                        MyFeedbackRow(ticket: ticket)
                    }
                    .listRowBackground(Color.portalCard)
                }
                .portalList()
                .refreshable { await model.load() }
            }
        }
    }
}

/// MyFeedbackRow is one piece of feedback: the person's words without the prefix the server put on the title, the status of the
/// ticket in the words the Tickets tab uses, and the day it was sent.
struct MyFeedbackRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PortalFeedback.shownWords(title: ticket.title))
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
            HStack(alignment: .firstTextBaseline) {
                if let status = ticket.status {
                    Label(TicketText.status(status), systemImage: ticket.isOpenForWork ? "circle.dotted" : "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let sentDate = PortalDate.parse(ticket.createdAt) {
                    Text(sentDate, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("myFeedbackRow")
    }
}
