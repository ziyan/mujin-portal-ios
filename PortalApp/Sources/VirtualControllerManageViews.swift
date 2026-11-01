import PortalKit
import SwiftUI

/// VirtualControllerManageRows are the actions on a virtual controller: pause or resume, edit and destroy. Each shows only
/// when the viewer holds its capability at the site, so nobody sees a button the server would refuse.
struct VirtualControllerManageRows: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let virtual: VirtualControllerSummary
    let onChange: (VirtualControllerSummary) -> Void
    let onDestroyed: () -> Void

    @State private var isEditing = false
    @State private var isConfirmingDestroy = false
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        if virtual.canTogglePause {
            Button {
                Task { await togglePause() }
            } label: {
                Label(virtual.isPaused ? "Resume" : "Pause", systemImage: virtual.isPaused ? "play.circle" : "pause.circle")
            }
            .disabled(isWorking)
        }
        if virtual.canModify {
            Button { isEditing = true } label: { Label("Edit", systemImage: "pencil") }
                .disabled(isWorking)
                .sheet(isPresented: $isEditing) {
                    VirtualControllerEditView(virtual: virtual) { updated in
                        onChange(updated)
                    }
                }
        }
        if virtual.canDestroy {
            Button(role: .destructive) {
                isConfirmingDestroy = true
            } label: {
                Label("Destroy", systemImage: "trash")
            }
            .disabled(isWorking)
            .confirmationDialog("Destroy this virtual controller?", isPresented: $isConfirmingDestroy, titleVisibility: .visible) {
                Button("Destroy \(virtual.displayName)", role: .destructive) { Task { await destroy() } }
            } message: {
                Text("Its data and snapshots go with it. This cannot be undone.")
            }
        }
        if let errorText {
            Text(errorText).font(.footnote).foregroundStyle(Color.statusError)
        }
    }

    private func togglePause() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        let connection = appModel.connection(for: session.account)
        do {
            try await connection.setVirtualControllerPaused(id: virtual.id, paused: !virtual.isPaused)
            onChange(try await connection.virtualController(id: virtual.id))
            session.cache.clear(accountKey: session.account.accountKey)
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }

    private func destroy() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await appModel.connection(for: session.account).destroyVirtualController(id: virtual.id)
            session.cache.clear(accountKey: session.account.accountKey)
            onDestroyed()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}

/// VirtualControllerEditView changes a virtual controller's name, comment and size.
struct VirtualControllerEditView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let virtual: VirtualControllerSummary
    let onSaved: (VirtualControllerSummary) -> Void

    @State private var name: String
    @State private var comment: String
    @State private var size: String
    @State private var sizes: [VirtualControllerSize] = []
    @State private var isSaving = false
    @State private var errorText: String?

    init(virtual: VirtualControllerSummary, onSaved: @escaping (VirtualControllerSummary) -> Void) {
        self.virtual = virtual
        self.onSaved = onSaved
        _name = State(initialValue: virtual.name ?? "")
        _comment = State(initialValue: virtual.comment ?? "")
        _size = State(initialValue: virtual.size ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Comment", text: $comment, axis: .vertical)
                }
                if !sizes.isEmpty {
                    Section {
                        Picker("Size", selection: $size) {
                            ForEach(sizes) { option in Text(option.shownName).tag(option.name) }
                        }
                    }
                }
                if let errorText {
                    Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.portalPage)
            .navigationTitle("Edit virtual controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { sizes = (try? await appModel.connection(for: session.account).virtualControllerSizes()) ?? [] }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            let updated = try await appModel.connection(for: session.account).modifyVirtualController(
                id: virtual.id, name: name.trimmingCharacters(in: .whitespaces), comment: comment,
                size: size.isEmpty || size == virtual.size ? nil : size)
            session.cache.clear(accountKey: session.account.accountKey)
            onSaved(updated)
            dismiss()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}
