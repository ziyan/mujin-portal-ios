import PortalKit
import SwiftUI

/// VirtualControllerSnapshotsView lists a virtual controller's snapshots and lets the viewer make one, restore to one, rename
/// one and delete one, each only when the viewer holds the capability.
struct VirtualControllerSnapshotsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let virtual: VirtualControllerSummary

    @State private var snapshots: [VirtualControllerSnapshot] = []
    @State private var phase = LoadPhase.loading
    @State private var errorText: String?
    @State private var isCreating = false
    @State private var newComment = ""
    @State private var renaming: VirtualControllerSnapshot?
    @State private var renamedComment = ""
    @State private var restoring: VirtualControllerSnapshot?
    @State private var deleting: VirtualControllerSnapshot?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Could not load snapshots", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            case .loaded:
                list
            }
        }
        .navigationTitle("Snapshots")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenCompact()
        .toolbar {
            if virtual.canModify {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newComment = ""; isCreating = true } label: { Label("New snapshot", systemImage: "plus") }
                }
            }
        }
        .alert("New snapshot", isPresented: $isCreating) {
            TextField("Comment", text: $newComment)
            Button("Create") { Task { await create() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename snapshot", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Comment", text: $renamedComment)
            Button("Save") { if let snapshot = renaming { Task { await rename(snapshot) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Restore this snapshot?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible, presenting: restoring) { snapshot in
            Button("Restore", role: .destructive) { Task { await restore(snapshot) } }
        } message: { _ in
            Text("The virtual controller goes back to this state. Changes made since are lost.")
        }
        .confirmationDialog("Delete this snapshot?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { snapshot in
            Button("Delete", role: .destructive) { Task { await delete(snapshot) } }
        } message: { _ in
            Text("This cannot be undone.")
        }
        .task { await load() }
    }

    private var list: some View {
        List { PortalRows {
            if let errorText {
                Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) }
            }
            if snapshots.isEmpty {
                Section { Text("No snapshots yet.").foregroundStyle(.secondary) }
            }
            ForEach(snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.shownName).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let date = snapshot.date { Text(date, format: .dateTime.month().day().year().hour().minute()) }
                        if !snapshot.isReady { Text(LocalizedStringKey(snapshot.status ?? "")) }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    if let message = snapshot.statusMessage, !message.isEmpty, !snapshot.isReady {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if virtual.canDestroy {
                        Button("Delete", role: .destructive) { deleting = snapshot }
                    }
                    if virtual.canModify {
                        Button("Rename") { renamedComment = snapshot.comment ?? ""; renaming = snapshot }
                            .tint(.gray)
                    }
                }
                .swipeActions(edge: .leading) {
                    if virtual.canModify, snapshot.canRestore {
                        Button("Restore") { restoring = snapshot }
                            .tint(.accentColor)
                    }
                }
            }
        } }
        .portalList()
        .refreshable { await load() }
    }

    private func load() async {
        do {
            snapshots = try await appModel.connection(for: session.account).snapshots(virtualControllerId: virtual.id)
            phase = .loaded
        } catch {
            appModel.handle(error, account: session.account)
            if snapshots.isEmpty { phase = .failed(error.userMessage) }
        }
    }

    private func create() async {
        await run { connection in
            _ = try await connection.createSnapshot(virtualControllerId: virtual.id, comment: newComment.trimmingCharacters(in: .whitespaces))
        }
    }

    private func rename(_ snapshot: VirtualControllerSnapshot) async {
        await run { connection in _ = try await connection.renameSnapshot(id: snapshot.id, comment: renamedComment.trimmingCharacters(in: .whitespaces)) }
    }

    private func restore(_ snapshot: VirtualControllerSnapshot) async {
        await run { connection in try await connection.restoreSnapshot(id: snapshot.id) }
    }

    private func delete(_ snapshot: VirtualControllerSnapshot) async {
        await run { connection in try await connection.destroySnapshot(id: snapshot.id) }
    }

    /// Runs one change, then reads the list again, showing the server's words when it refuses.
    private func run(_ change: (Connection) async throws -> Void) async {
        errorText = nil
        let connection = appModel.connection(for: session.account)
        do {
            try await change(connection)
            await load()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}
