import Observation
import PortalKit
import SwiftUI

/// TicketDetailModel is one open ticket with its thread.
@MainActor
@Observable
final class TicketDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let ticketId: String
    let connection: Connection
    let onError: @MainActor (Error) -> Void
    private(set) var phase = Phase.loading
    private(set) var ticket: Ticket?
    private(set) var comments: [TicketComment] = []
    private(set) var isSending = false
    var actionError: String?

    init(ticketId: String, connection: Connection, onError: @escaping @MainActor (Error) -> Void) {
        self.ticketId = ticketId
        self.connection = connection
        self.onError = onError
    }

    func load() async {
        do {
            async let loadedTicket = connection.ticket(id: ticketId)
            async let loadedComments = connection.ticketComments(ticketId: ticketId)
            let (newTicket, newComments) = try await (loadedTicket, loadedComments)
            ticket = newTicket
            comments = newComments
            phase = .loaded
        } catch {
            onError(error)
            if phase == .loading { phase = .failed(error.userMessage) }
        }
    }

    /// Sends a comment with the files picked for it. The files go up first and
    /// the comment refers to them; a failure leaves everything as it was.
    func comment(text: String, drafts: AttachmentDrafts, isInternal: Bool) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !drafts.items.isEmpty, !isSending else { return false }
        isSending = true
        actionError = nil
        defer { isSending = false }
        do {
            let files = try await drafts.upload(using: connection)
            try await connection.addTicketComment(
                ticketId: ticketId, body: SharePayload.ticketDescription(text: trimmed, files: files), isInternal: isInternal)
            drafts.clear()
            await load()
            return true
        } catch {
            actionError = error.userMessage
            onError(error)
            return false
        }
    }

    func setClosed(_ isClosed: Bool) async {
        do {
            if isClosed { try await connection.closeTicket(id: ticketId) } else { try await connection.reopenTicket(id: ticketId) }
            await load()
        } catch {
            actionError = error.userMessage
            onError(error)
        }
    }
}

/// TicketDetailView is a ticket: what it is about, the thread, and a way to reply.
struct TicketDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let ticketId: String

    @State private var model: TicketDetailModel?
    @State private var draft = ""
    @State private var drafts = AttachmentDrafts()
    @State private var isInternal = false
    @State private var isConfirmingClose = false
    @State private var isLinkCopied = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let ticket = model?.ticket {
                ToolbarItem(placement: .topBarTrailing) {
                    DetailMenu(demoScreen: "ticket-menu") {
                        if let sequence = ticket.sequence {
                            Section { LinkMenuItems(link: .ticket(sequence: sequence), isCopied: $isLinkCopied) }
                        }
                        Section { AskAboutButton(viewing: Viewing(kind: "ticket", id: ticket.id), subject: ticket.displayName) }
                        Section {
                            if ticket.isOpenForWork || ticket.status == "solved" {
                                Button(role: .destructive) {
                                    isConfirmingClose = true
                                } label: {
                                    Label("Close ticket", systemImage: "checkmark.circle")
                                }
                            } else if ticket.status == "closed" {
                                Button { Task { await model?.setClosed(false) } } label: { Label("Reopen ticket", systemImage: "arrow.uturn.backward") }
                            }
                        }
                    }
                    .confirmationDialog("Close this ticket?", isPresented: $isConfirmingClose, titleVisibility: .visible) {
                        Button("Close ticket", role: .destructive) { Task { await model?.setClosed(true) } }
                    } message: {
                        Text("You can reopen it later.")
                    }
                }
            }
        }
        .attachmentPickers(drafts)
        .linkCopiedToast($isLinkCopied)
        .demoMenuHost(screen: "ticket-menu")
        .hidesTabBarWhenCompact()
        .task(id: ticketId) {
            let detailModel = TicketDetailModel(
                ticketId: ticketId, connection: appModel.connection(for: session.account),
                onError: { [appModel, session] error in appModel.handle(error, account: session.account) })
            model = detailModel
            await detailModel.load()
            await session.loadPeople(
                detailModel.comments.compactMap(\.authorUserId) + [detailModel.ticket?.requesterUserId, detailModel.ticket?.assigneeUserId].compactMap { $0 })
            // New replies arrive while the screen is open; the web app is told by a subscription, this polls.
            while !Task.isCancelled && !appModel.isDemo {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if Task.isCancelled { return }
                await detailModel.load()
            }
        }
    }

    private var navigationTitleText: String {
        guard let sequence = model?.ticket?.sequence else { return "" }
        return "#\(sequence)"
    }

    @ViewBuilder
    private func content(_ model: TicketDetailModel) -> some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load this ticket", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
            }
        case .loaded:
            if let ticket = model.ticket {
                thread(model, ticket: ticket)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        composer(model, ticket: ticket)
                    }
            }
        }
    }

    private func thread(_ model: TicketDetailModel, ticket: Ticket) -> some View {
        ScrollView {
            // Not lazy: scrolling this thread could leave a lazy stack placing its rows forever, with the app frozen at full CPU.
            VStack(alignment: .leading, spacing: 16) {
                header(ticket)
                if model.comments.isEmpty, let description = ticket.description, !description.isEmpty {
                    CommentView(authorName: session.name(ofPerson: ticket.authorUserId), authorUserId: ticket.authorUserId, date: ticket.lastActivity, text: description, isInternal: false, connection: model.connection)
                }
                ForEach(model.comments) { comment in
                    CommentView(
                        authorName: session.name(ofPerson: comment.authorUserId), authorUserId: comment.authorUserId, date: comment.date, text: comment.isRemoved ? "" : (comment.body ?? ""),
                        isInternal: comment.isInternal == true, connection: model.connection)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.portalPage)
    }

    private func header(_ ticket: Ticket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ticket.title ?? "")
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                if let status = ticket.status {
                    Label(TicketText.status(status), systemImage: ticket.isOpenForWork ? "circle.dotted" : "checkmark.circle")
                }
                if let priority = ticket.priority, priority == "high" || priority == "urgent" {
                    Label(TicketText.priority(priority), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusWarning)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Requested by \(session.name(ofPerson: ticket.requesterUserId ?? ticket.authorUserId))")
                if let assignee = ticket.assigneeIds.first {
                    Text("Assigned to \(session.name(ofPerson: assignee))")
                }
                if let name = session.siteNames[ticket.siteId ?? ""], !name.isEmpty {
                    Text("Site: \(name)")
                }
                if session.isStaff, let name = session.organizationNames[ticket.organizationId ?? ""], !name.isEmpty {
                    Text("Organization: \(name)")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func composer(_ model: TicketDetailModel, ticket: Ticket) -> some View {
        VStack(spacing: 6) {
            if let error = model.actionError ?? drafts.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.statusError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            AttachmentStrip(drafts: drafts)
                .padding(.horizontal, 20)
            ComposerCard(
                placeholder: isInternal ? LocalizedStringKey("Internal note") : LocalizedStringKey("Reply"), text: $draft, drafts: drafts,
                canSend: !model.isSending && !(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && drafts.items.isEmpty),
                isSending: model.isSending, fieldIdentifier: "replyField",
                onSend: {
                    let text = draft
                    Task {
                        if await model.comment(text: text, drafts: drafts, isInternal: isInternal) { draft = "" }
                    }
                },
                accessory: {
                    // Staff choose here whether a reply is an internal note: a lock chip in the card, not a row of its own.
                    if session.isStaff {
                        Button {
                            isInternal.toggle()
                        } label: {
                            Label("Internal note", systemImage: isInternal ? "lock.fill" : "lock.open")
                                .labelStyle(.iconOnly)
                                .font(.body.weight(.medium))
                                .foregroundStyle(isInternal ? Color.onAccent : Color.secondary)
                                .frame(width: 36, height: 36)
                                .background(isInternal ? AnyShapeStyle(Color.statusWarning) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .circle)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Internal note")
                        .accessibilityValue(isInternal ? Text("On") : Text("Off"))
                    }
                })
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

/// CommentView is one comment: who wrote it, when, and its words and files.
private struct CommentView: View {
    let authorName: String
    var authorUserId: String?
    let date: Date?
    let text: String
    let isInternal: Bool
    let connection: Connection

    var bodyView: some View {
        RichBodyView(markdown: text, connection: connection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                UserAvatar(userId: authorUserId, name: authorName, size: 24)
                Text(authorName).font(.subheadline.weight(.semibold))
                if isInternal {
                    Label("Internal", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.statusWarning)
                }
                Spacer(minLength: 8)
                if let date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if text.isEmpty {
                Text("This comment was removed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                bodyView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isInternal ? Color.statusWarning.opacity(0.12) : Color.portalCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
