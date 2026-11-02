import PortalKit
import SwiftUI

/// VirtualControllerMenu is the `...` menu of a virtual controller's page: copy its link, then pause or resume, edit and destroy.
/// Each action shows only when the viewer holds its capability at the site, so nobody sees a button the server would refuse.
/// The destroy confirmation hangs from the menu button, and the editor and the error from the page.
struct VirtualControllerMenu: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let virtual: VirtualControllerSummary
    @Binding var isLinkCopied: Bool
    let onChange: (VirtualControllerSummary) -> Void
    let onDestroyed: () -> Void

    @State private var isEditing = false
    @State private var isConfirmingDestroy = false
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        DetailMenu(demoScreen: "virtual-controller-menu") {
            Section { LinkMenuItems(link: .virtualController(id: virtual.id), isCopied: $isLinkCopied) }
            if virtual.canTogglePause || virtual.canModify {
                Section {
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
                    }
                }
            }
            if virtual.canDestroy {
                Section {
                    Button(role: .destructive) {
                        isConfirmingDestroy = true
                    } label: {
                        Label("Destroy", systemImage: "trash")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .confirmationDialog("Destroy this virtual controller?", isPresented: $isConfirmingDestroy, titleVisibility: .visible) {
            Button("Destroy \(virtual.displayName)", role: .destructive) { Task { await destroy() } }
        } message: {
            Text("Its data and snapshots go with it. This cannot be undone.")
        }
        .sheet(isPresented: $isEditing) {
            VirtualControllerEditView(virtual: virtual) { updated in
                onChange(updated)
            }
        }
        .alert("Could not change it", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
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

/// VirtualControllerCreateView makes a virtual controller at a site, from the sizes, products and regions the server offers.
struct VirtualControllerCreateView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let siteId: String
    let onCreated: (VirtualControllerSummary) -> Void

    @State private var name = ""
    @State private var comment = ""
    @State private var size = ""
    @State private var product = ""
    @State private var region = ""
    @State private var options = VirtualControllerOptions()
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Comment", text: $comment, axis: .vertical)
                }
                Section {
                    if !options.sizes.isEmpty {
                        Picker("Size", selection: $size) { ForEach(options.sizes) { Text($0.shownName).tag($0.name) } }
                    }
                    if !options.products.isEmpty {
                        Picker("Product", selection: $product) { ForEach(options.products) { Text($0.shownName).tag($0.name) } }
                    }
                    if !options.regions.isEmpty {
                        Picker("Region", selection: $region) { ForEach(options.regions) { Text($0.region).tag($0.region) } }
                    }
                }
                if let errorText {
                    Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.portalPage)
            .navigationTitle("New virtual controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || size.isEmpty)
                }
            }
            .task {
                guard let loaded = try? await appModel.connection(for: session.account).virtualControllerOptions() else { return }
                options = loaded
                if size.isEmpty { size = loaded.sizes.first?.name ?? "" }
                if product.isEmpty { product = loaded.products.first?.name ?? "" }
                if region.isEmpty { region = loaded.defaultRegion ?? "" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() async {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            let created = try await appModel.connection(for: session.account).createVirtualController(
                siteId: siteId, name: name.trimmingCharacters(in: .whitespaces), comment: comment, size: size, product: product, region: region)
            session.cache.clear(accountKey: session.account.accountKey)
            onCreated(created)
            dismiss()
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}

/// VirtualControllerCreateButton is the plus in the virtual controllers list, shown to people who may create one.
struct VirtualControllerCreateButton: View {
    @Environment(SessionModel.self) private var session
    let model: SiteModel
    @State private var isCreating = false

    var body: some View {
        if VirtualControllerCreateAccess.canOffer(site: model.selectedSite), let siteId = model.selectedSiteId {
            Button { isCreating = true } label: { Label("New virtual controller", systemImage: "plus") }
                .sheet(isPresented: $isCreating) {
                    VirtualControllerCreateView(siteId: siteId) { _ in
                        Task { await model.loadDetails(force: true) }
                    }
                }
        }
    }
}
