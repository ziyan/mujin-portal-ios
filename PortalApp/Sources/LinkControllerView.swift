import PortalKit
import SwiftUI

/// LinkControllerView approves a controller that is waiting for a link code: the person types the code the controller shows,
/// sees which controller it is, picks a site of their organization and approves.
struct LinkControllerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var found: ControllerSummary?
    @State private var hasLooked = false
    @State private var sites: [SiteSummary] = []
    @State private var siteId = ""
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await look() } }
                    Button("Look up") { Task { await look() } }
                        .disabled(isWorking || ControllerLinkAccess.normalized(code).isEmpty)
                }
                if let found {
                    Section("Controller") {
                        LabeledContent("Controller") { Text(found.displayName) }
                        if let detail = found.detail { LabeledContent("Comment") { Text(detail) } }
                        if !sites.isEmpty {
                            Picker("Site", selection: $siteId) {
                                Text("No site").tag("")
                                ForEach(sites) { Text($0.name ?? $0.id).tag($0.id) }
                            }
                        }
                        Button("Approve") { Task { await approve() } }.disabled(isWorking)
                    }
                } else if hasLooked {
                    Section { Text("No controller is waiting for that code.").foregroundStyle(.secondary) }
                }
                if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.portalPage)
            .navigationTitle("Link a controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func look() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        let connection = appModel.connection(for: session.account)
        do {
            found = try await connection.controllerLink(code: code)
            hasLooked = true
            if found != nil {
                let own = session.profile?.me.organizationId
                sites = ((try? await connection.allSites()) ?? []).filter { $0.organizationId == own && $0.isArchived != true }
            }
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }

    private func approve() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await appModel.connection(for: session.account).approveControllerLink(code: code, siteId: siteId)
            session.cache.clear(accountKey: session.account.accountKey)
            dismiss()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}
