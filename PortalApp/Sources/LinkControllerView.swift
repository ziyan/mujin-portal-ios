import AVFoundation
import PortalKit
import SwiftUI

/// LinkControllerView links a controller that shows a QR code. The person points the camera at the code, sees which controller it is,
/// picks a site of their organization and approves. Typing the code is the way out when the camera cannot be used.
struct LinkControllerView: View {
    let request: ControllerLinkRequest

    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Where the person is in the flow.
    enum Step: Equatable {
        case scanning
        case typing
        case confirm(code: String)
        case otherServer(host: String)
        case linked
    }

    enum CameraAccess { case unknown, allowed, denied }

    @State private var step: Step
    @State private var camera = CameraAccess.unknown
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    @State private var typedText = ""
    @State private var found: ControllerSummary?
    @State private var hasLooked = false
    @State private var sites: [SiteSummary] = []
    @State private var siteId = ""
    @State private var isWorking = false
    @State private var errorText: String?

    init(request: ControllerLinkRequest) {
        self.request = request
        if let code = request.code {
            _step = State(initialValue: .confirm(code: code))
        } else if let host = request.otherServerHost {
            _step = State(initialValue: .otherServer(host: host))
        } else {
            _step = State(initialValue: .scanning)
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Link a controller")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if step != .linked {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                }
        }
        .task { await start() }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings with the camera allowed.
            if phase == .active, step == .scanning, camera == .denied { Task { await refreshCamera(asking: false) } }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .scanning:
            if camera == .denied { deniedView } else { scanView }
        case .typing:
            typingView
        case .confirm:
            confirmView
        case .otherServer(let host):
            ContentUnavailableView {
                Label("Another Portal server", systemImage: "server.rack")
            } description: {
                Text("This code is for \(host), not \(session.account.server.displayHost). Sign in to that server to link it.")
            } actions: {
                Button("Scan again") { resetToScanning() }
            }
        case .linked:
            ContentUnavailableView {
                Label("Controller linked", systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text("It now belongs to your organization.")
            } actions: {
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Scanning

    private var scanView: some View {
        ZStack {
            scannerSurface.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Point the camera at the QR code on the controller's screen")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                if let note {
                    Text(note)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("Enter the code instead") { step = .typing }
                    .buttonStyle(.bordered)
                    .padding(4)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding(16)
        }
    }

    @ViewBuilder private var scannerSurface: some View {
        if appModel.isDemo {
            DemoScannerPlaceholder { scanned(ControllerLinkPayload.address(code: DemoServer.linkCode, server: session.account.server)) }
        } else if camera == .allowed {
            QRScannerView { text in scanned(text) }
        } else {
            Color.black
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Camera access is off", systemImage: "video.slash")
        } description: {
            Text("Allow camera access in Settings to scan the QR code on a controller.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
            Button("Enter the code instead") { step = .typing }
        }
    }

    private func refreshCamera(asking: Bool) async {
        if appModel.isDemo {
            camera = DemoOptions.screen == "link-denied" ? .denied : .allowed
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera = .allowed
        case .notDetermined:
            if asking {
                camera = await AVCaptureDevice.requestAccess(for: .video) ? .allowed : .denied
            }
        default:
            camera = .denied
        }
    }

    private func scanned(_ text: String) {
        guard step == .scanning, !isWorking else { return }
        switch ControllerLinkPayload.read(text, server: session.account.server) {
        case .link(let code):
            showNote(nil)
            begin(code: code)
        case .otherServer(let host):
            showNote(String(localized: "This code is for \(host), not \(session.account.server.displayHost). Sign in to that server to link it."))
        case .notControllerCode:
            showNote(String(localized: "This is not a controller code"))
        }
    }

    /// Says something short over the camera and takes it away again, while scanning goes on.
    private func showNote(_ text: String?) {
        noteTask?.cancel()
        note = text
        guard text != nil else { return }
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { note = nil }
        }
    }

    // MARK: Typing

    private var typingView: some View {
        Form {
            Section {
                TextField("Link code or address", text: $typedText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { lookUpTyped() }
                Button("Look up") { lookUpTyped() }
                    .disabled(isWorking || typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Type or paste the code or address shown with the QR code.")
            }
            Section {
                Button("Scan the QR code instead") {
                    errorText = nil
                    step = .scanning
                    Task { await refreshCamera(asking: true) }
                }
            }
            if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(Color.statusError) } }
        }
        .scrollContentBackground(.hidden)
        .background(Color.portalPage)
    }

    private func lookUpTyped() {
        errorText = nil
        switch ControllerLinkPayload.read(typedText, server: session.account.server) {
        case .link(let code): begin(code: code)
        case .otherServer(let host):
            errorText = String(localized: "This code is for \(host), not \(session.account.server.displayHost). Sign in to that server to link it.")
        case .notControllerCode:
            errorText = String(localized: "This is not a controller code")
        }
    }

    // MARK: Confirming

    private var confirmView: some View {
        Form {
            if let found {
                Section {
                    LabeledContent("Controller") { Text(found.displayName) }
                    if let detail = found.detail { LabeledContent("Comment") { Text(detail) } }
                    if let organizationName = session.profile?.organizationName {
                        LabeledContent("Organization") { Text(organizationName) }
                    }
                    if !sites.isEmpty {
                        Picker("Site", selection: $siteId) {
                            Text("No site").tag("")
                            ForEach(sites) { Text($0.name ?? $0.id).tag($0.id) }
                        }
                    }
                } header: {
                    Text("Controller")
                } footer: {
                    Text("Approving links this controller to your organization.")
                }
                Section {
                    Button("Approve") { Task { await approve() } }.disabled(isWorking)
                }
            } else if isWorking || !hasLooked {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking up the controller").foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    if errorText == nil { Text("No controller is waiting for that code.").foregroundStyle(.secondary) }
                    Button("Scan again") { resetToScanning() }
                }
            }
            if let errorText {
                Section {
                    Text(errorText).font(.footnote).foregroundStyle(Color.statusError)
                    if found == nil { Button("Scan again") { resetToScanning() } }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.portalPage)
    }

    private func begin(code: String) {
        found = nil
        hasLooked = false
        errorText = nil
        step = .confirm(code: code)
        Task { await look(code: code) }
    }

    private func resetToScanning() {
        found = nil
        hasLooked = false
        errorText = nil
        step = .scanning
        Task { await refreshCamera(asking: true) }
    }

    private func start() async {
        if case .confirm(let code) = step {
            await look(code: code)
        } else {
            await refreshCamera(asking: true)
        }
    }

    private func look(code: String) async {
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
            hasLooked = true
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }

    private func approve() async {
        guard case .confirm(let code) = step else { return }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await appModel.connection(for: session.account).approveControllerLink(code: code, siteId: siteId)
            session.cache.clear(accountKey: session.account.accountKey)
            step = .linked
        } catch {
            appModel.handle(error, account: session.account)
            errorText = error.userMessage
        }
    }
}

/// DemoScannerPlaceholder stands in for the camera where there is none, such as the simulator. A tap on it plays a scan.
private struct DemoScannerPlaceholder: View {
    let onTap: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 160, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.45))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityLabel("Camera preview")
        .accessibilityAddTraits(.isButton)
    }
}
