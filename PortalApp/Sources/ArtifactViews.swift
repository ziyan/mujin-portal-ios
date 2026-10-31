import PortalKit
import SwiftUI
import UIKit
import WebKit

/// ArtifactWebView shows a page the assistant made. It is a web view with
/// nothing the page can call: no script bridge, a private data store, and a
/// content rule list that blocks every address except the server the page
/// came from. The server adds its own sandbox on the response. The theme
/// travels in the address fragment, so changing it does not reload the page.
struct ArtifactWebView: UIViewRepresentable {
    enum Source {
        case remote(artifactId: String)
        /// A page held in memory, for the demo.
        case html(String)
    }

    let source: Source
    let connection: Connection
    let isDark: Bool
    /// Inline pages are as tall as their content, between 120 and 640 points.
    let isInline: Bool
    @Binding var height: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, isInline: isInline)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = !isInline
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.begin(webView: webView, source: source, connection: connection, isDark: isDark)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(isDark: isDark)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let height: Binding<Double>
        private let isInline: Bool
        private weak var webView: WKWebView?
        private var isDark = false
        private var allowedURL: URL?
        private var loadTask: Task<Void, Never>?
        private var measureTask: Task<Void, Never>?

        init(height: Binding<Double>, isInline: Bool) {
            self.height = height
            self.isInline = isInline
        }

        func begin(webView: WKWebView, source: Source, connection: Connection, isDark: Bool) {
            self.webView = webView
            self.isDark = isDark
            loadTask = Task { [weak self] in
                switch source {
                case .html(let html):
                    webView.loadHTMLString(html, baseURL: nil)
                case .remote(let artifactId):
                    let server = await connection.server
                    // Without the rule list the page would not be contained, so it is not shown.
                    guard await Self.install(rules: ArtifactSandbox.contentRuleListJSON(server: server), on: webView) else { return }
                    guard let token = try? await connection.accessToken() else { return }
                    let url = await connection.artifactPageURL(id: artifactId, isDark: isDark)
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    self?.allowedURL = url
                    webView.load(request)
                }
            }
        }

        private static func install(rules: String, on webView: WKWebView) async -> Bool {
            do {
                let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "artifact-sandbox", encodedContentRuleList: rules)
                guard let list else { return false }
                webView.configuration.userContentController.add(list)
                return true
            } catch {
                return false
            }
        }

        /// Hands the page the new theme by changing only the fragment.
        func apply(isDark: Bool) {
            guard isDark != self.isDark else { return }
            self.isDark = isDark
            webView?.evaluateJavaScript("location.hash = '\(ArtifactSandbox.themeFragment(isDark: isDark))'")
        }

        // MARK: WKNavigationDelegate

        /// The page itself loads once; nothing it links to opens in it.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else { return .cancel }
            if url.scheme == "about" || url.scheme == "data" { return .allow }
            guard let allowedURL else { return .cancel }
            let isSamePage = url.absoluteString.split(separator: "#").first == allowedURL.absoluteString.split(separator: "#").first
            return isSamePage ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard isInline else { return }
            // Charts draw after the load, so the height is read again a few times.
            measureTask?.cancel()
            measureTask = Task { [weak self] in
                for pause in [0.0, 0.5, 1.5, 3.0] {
                    try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                    if Task.isCancelled { return }
                    await self?.measure()
                }
            }
        }

        private func measure() async {
            guard let webView else { return }
            let measured = try? await webView.evaluateJavaScript("document.documentElement.scrollHeight")
            if let number = measured as? NSNumber {
                height.wrappedValue = ArtifactSandbox.clampedHeight(number.doubleValue)
            }
        }
    }
}

/// ArtifactCardView is a page, drawing or document the assistant made, shown
/// under the tool line. A tap on the title opens it full size.
struct ArtifactCardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    let artifact: ArtifactReference
    let connection: Connection
    let onOpen: () -> Void

    @State private var height = 220.0
    @State private var markdown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: artifact.kind == .markdown ? "doc.text" : "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(artifact.title.isEmpty ? String(localized: "Artifact") : artifact.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            content
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Open full size"), onOpen)
        .contextMenu {
            Button(action: onOpen) { Label("Open full size", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
    }


    private var pageSource: ArtifactWebView.Source {
        appModel.isDemo ? ArtifactWebView.Source.html(DemoArtifact.html(isDark: colorScheme == .dark)) : ArtifactWebView.Source.remote(artifactId: artifact.id)
    }

    private func loadMarkdown() async -> String? {
        if appModel.isDemo { return DemoArtifact.markdown }
        return try? await connection.artifactText(id: artifact.id)
    }

    @ViewBuilder
    private var content: some View {
        if artifact.kind == .markdown {
            MarkdownView(markdown: markdown ?? "")
                .frame(maxHeight: 320, alignment: .top)
                .clipped()
                .task(id: artifact.id) {
                    markdown = await loadMarkdown()
                }
        } else {
            ArtifactWebView(
                source: pageSource,
                connection: connection, isDark: colorScheme == .dark, isInline: true, height: $height
            )
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// ArtifactFullView shows an artifact at full size, with the means to save it.
struct ArtifactFullView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let artifact: ArtifactReference
    let connection: Connection

    @State private var height = 0.0
    @State private var markdown: String?
    @State private var download: ExportedArtifact?
    @State private var downloadError: String?

    struct ExportedArtifact: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            Group {
                if artifact.kind == .markdown {
                    ScrollView {
                        MarkdownView(markdown: markdown ?? "")
                            .padding(16)
                    }
                    .task(id: artifact.id) {
                        markdown = await loadMarkdown()
                    }
                } else {
                    ArtifactWebView(
                        source: pageSource,
                        connection: connection, isDark: colorScheme == .dark, isInline: false, height: $height
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(artifact.title.isEmpty ? String(localized: "Artifact") : artifact.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await saveDownload() }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let downloadError {
                    Text(downloadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
        }
        .sheet(item: $download) { file in
            FileExporter(url: file.url)
        }
    }


    private var pageSource: ArtifactWebView.Source {
        appModel.isDemo ? ArtifactWebView.Source.html(DemoArtifact.html(isDark: colorScheme == .dark)) : ArtifactWebView.Source.remote(artifactId: artifact.id)
    }

    private func loadMarkdown() async -> String? {
        if appModel.isDemo { return DemoArtifact.markdown }
        return try? await connection.artifactText(id: artifact.id)
    }

    private func saveDownload() async {
        downloadError = nil
        do {
            let data: Data
            if appModel.isDemo {
                data = Data(DemoArtifact.markdown.utf8)
            } else {
                data = try await connection.artifactData(id: artifact.id, isDownload: true)
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(ArtifactSandbox.downloadFileName(title: artifact.title, kind: artifact.kind))
            try data.write(to: file)
            download = ExportedArtifact(url: file)
        } catch {
            downloadError = error.userMessage
        }
    }
}

/// ProducedFileRow is a file a shell command wrote. An image shows in place;
/// anything else is a row that saves the file.
struct ProducedFileRow: View {
    @Environment(AppModel.self) private var appModel
    let file: ProducedFile
    let connection: Connection

    @State private var imageData: Data?
    @State private var exported: ArtifactFullView.ExportedArtifact?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if file.isImage, let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(Text(file.name))
            }
            HStack(spacing: 8) {
                Image(systemName: file.isImage ? "photo" : "doc")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let size = file.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await save() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Saves the file"))
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: file.attachmentId) {
            guard file.isImage, !appModel.isDemo else { return }
            imageData = try? await connection.fetch(path: file.url ?? "/api/v1/attachment/\(file.attachmentId)")
        }
        .sheet(item: $exported) { item in FileExporter(url: item.url) }
    }

    private func save() async {
        errorText = nil
        do {
            let data: Data
            if appModel.isDemo {
                data = Data("demo".utf8)
            } else {
                data = try await connection.fetch(path: file.url ?? "/api/v1/attachment/\(file.attachmentId)")
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("produced-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(file.name.replacingOccurrences(of: "/", with: "-"))
            try data.write(to: destination)
            exported = ArtifactFullView.ExportedArtifact(url: destination)
        } catch {
            errorText = error.userMessage
        }
    }
}

/// DemoArtifact is an invented page and document for screenshots.
enum DemoArtifact {
    static let markdown = """
        ## Weekly throughput

        - **site01** moved 1,240 pallets.
        - **site02** moved 980 pallets.

        > Numbers are invented for the demo.
        """

    static func html(isDark: Bool) -> String {
        let background = isDark ? "#1c1c1e" : "#ffffff"
        let text = isDark ? "#f2f2f7" : "#1c1c1e"
        let bar = isDark ? "#5ac8fa" : "#0a84ff"
        return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            body { font-family: -apple-system, sans-serif; margin: 0; padding: 12px; background: \(background); color: \(text); }
            .row { display: flex; align-items: center; margin: 8px 0; font-size: 15px; }
            .label { width: 64px; }
            .bar { height: 18px; border-radius: 4px; background: \(bar); }
            </style></head><body>
            <div class="row"><span class="label">site01</span><div class="bar" style="width: 220px"></div></div>
            <div class="row"><span class="label">site02</span><div class="bar" style="width: 174px"></div></div>
            <div class="row"><span class="label">site03</span><div class="bar" style="width: 96px"></div></div>
            </body></html>
            """
    }
}
