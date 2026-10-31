import PortalKit
import SwiftUI

/// TicketCreateView opens a ticket: a title, what happened, the site, how
/// urgent, and photos or files.
struct TicketCreateView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var priority = "normal"
    @State private var siteId = ""
    @State private var sites: [SiteSummary] = []
    @State private var drafts = AttachmentDrafts()
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form { PortalRows {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("ticketTitleField")
                    TextField("What happened?", text: $details, axis: .vertical)
                        .lineLimit(4...12)
                }
                Section {
                    Picker("Site", selection: $siteId) {
                        Text("Not about a site").tag("")
                        ForEach(sites) { site in
                            Text(site.name ?? site.id).tag(site.id)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low")
                        Text("Normal").tag("normal")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                }
                Section("Photos and files") {
                    AttachmentStrip(drafts: drafts)
                    AttachMenu(drafts: drafts)
                    if let message = drafts.errorText {
                        Text(message).font(.footnote).foregroundStyle(Color.statusError)
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Color.statusError) }
                }
            } }
.portalList()
            .navigationTitle("New ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .attachmentPickers(drafts)
            .task {
                sites = (try? await appModel.connection(for: session.account).sites()) ?? []
                if siteId.isEmpty, sites.count == 1 { siteId = sites[0].id }
            }
        }
    }

    private func create() async {
        isSending = true
        errorText = nil
        defer { isSending = false }
        do {
            let connection = appModel.connection(for: session.account)
            let files = try await drafts.upload(using: connection)
            let ticketId = try await connection.createTicket(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: SharePayload.ticketDescription(text: details, files: files), siteId: siteId.isEmpty ? nil : siteId, priority: priority)
            dismiss()
            onCreated(ticketId)
        } catch {
            errorText = error.userMessage
            appModel.handle(error, account: session.account)
        }
    }
}
