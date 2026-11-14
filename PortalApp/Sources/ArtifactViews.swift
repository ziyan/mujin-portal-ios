import PortalKit
import SwiftUI
import UIKit
import WebKit

/// ArtifactWebView shows a page the assistant made, as the web's frame does. The web view loads a frame of the app's own, which
/// holds the page in a frame sandboxed to its scripts: the page's origin is opaque, it has no cookies (the data store is private
/// and empty) and never sees the token, which only the app's own fetch carries. Every address but the app's scheme is blocked, and
/// nothing navigates away. The theme and title go in the page's address fragment, and the page's height comes back in a message.
struct ArtifactWebView: UIViewRepresentable {
    enum Source {
        case remote(artifactId: String)
        /// A page held in memory, for the demo.
        case html(String)
    }

    let source: Source
    let title: String
    let connection: Connection
    let isDark: Bool
    /// Inline pages are as tall as they say, between 120 and 640 points; the full-size one fills the screen.
    let isInline: Bool
    @Binding var height: Double
    /// Whether the height it starts at is the one this page measured before, so an early report of a half-drawn page is not taken.
    var isHeightRemembered = false

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, isInline: isInline, isHeightRemembered: isHeightRemembered)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            ArtifactSchemeHandler(source: source, connection: connection, frameHTML: { pageURL in
                ArtifactSandbox.frameHTML(pageURL: pageURL, frameTitle: title)
            }),
            forURLScheme: ArtifactSandbox.scheme)
        configuration.userContentController.add(context.coordinator, name: "artifactHeight")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.begin(webView: webView, pageURL: pageURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.show(pageURL)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "artifactHeight")
    }

    private var pageURL: URL {
        let artifactId = switch source {
        case .remote(let artifactId): artifactId
        case .html: "demo"
        }
        return ArtifactSandbox.pageURL(artifactId: artifactId, isDark: isDark, title: title)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let height: Binding<Double>
        private let isInline: Bool
        private let isHeightRemembered: Bool
        private weak var webView: WKWebView?
        private var shownPageURL: URL?
        private var loadTask: Task<Void, Never>?
        private var loadStartedAt = Date()

        init(height: Binding<Double>, isInline: Bool, isHeightRemembered: Bool) {
            self.height = height
            self.isInline = isInline
            self.isHeightRemembered = isHeightRemembered
        }

        func begin(webView: WKWebView, pageURL: URL) {
            self.webView = webView
            loadStartedAt = Date()
            shownPageURL = pageURL
            loadTask = Task {
                // Without the rule list the page would not be contained, so it is not shown.
                guard await Self.install(rules: ArtifactSandbox.contentRuleListJSON(), on: webView) else { return }
                // The theme can change while the rule list is made ready: the page loads at the address shown now.
                let latestPageURL = shownPageURL ?? pageURL
                var components = URLComponents(url: ArtifactSandbox.frameURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "page", value: latestPageURL.absoluteString)]
                webView.load(URLRequest(url: components.url!))
            }
        }

        /// Adds the rule list to the web view: the one compiled before for these very rules, else one compiled now. The identifier
        /// names the rules, so rules that change in a later version are compiled again rather than read stale.
        private static func install(rules: String, on webView: WKWebView) async -> Bool {
            let store = WKContentRuleListStore.default()
            let identifier = "artifact-frame-\(ArtifactSandbox.stableHash(rules))"
            do {
                let list: WKContentRuleList?
                if let compiled = try? await store?.contentRuleList(forIdentifier: identifier) {
                    list = compiled
                } else {
                    list = try await store?.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules)
                }
                guard let list else { return false }
                webView.configuration.userContentController.add(list)
                return true
            } catch {
                return false
            }
        }

        /// Hands the page a new theme by changing only the fragment of its address, which does not reload it.
        func show(_ pageURL: URL) {
            guard pageURL != shownPageURL else { return }
            shownPageURL = pageURL
            guard let quoted = try? String(data: JSONSerialization.data(withJSONObject: [pageURL.absoluteString]), encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.portalShowPage && window.portalShowPage(\(quoted)[0])")
        }

        /// The height the page reports, passed on by the frame. Only the app's frame can say it: the page's own frame is not heard.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard isInline, message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == ArtifactSandbox.scheme,
                let number = message.body as? NSNumber
            else { return }
            if let accepted = ArtifactSandbox.acceptedHeight(
                reported: number.doubleValue, current: height.wrappedValue, isRemembered: isHeightRemembered,
                secondsSinceLoad: Date().timeIntervalSince(loadStartedAt))
            {
                height.wrappedValue = accepted
            }
        }

        // MARK: WKNavigationDelegate

        /// The frame loads once, and the page once inside it with changes to its fragment; nothing either links to opens.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, url.scheme == ArtifactSandbox.scheme else { return .cancel }
            if navigationAction.targetFrame?.isMainFrame == true { return url.path == ArtifactSandbox.frameURL.path ? .allow : .cancel }
            guard let shown = shownPageURL else { return .cancel }
            return url.path == shown.path ? .allow : .cancel
        }
    }
}

/// ArtifactSchemeHandler serves the frame, the page and the artifact kit to an artifact's web view. The page's bytes are fetched
/// with the account's token by the app, never by the page, and served with the policy the server gives the web's frame.
@MainActor
final class ArtifactSchemeHandler: NSObject, WKURLSchemeHandler {
    private let source: ArtifactWebView.Source
    private let connection: Connection
    private let frameHTML: (URL) -> String
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(source: ArtifactWebView.Source, connection: Connection, frameHTML: @escaping (URL) -> String) {
        self.source = source
        self.connection = connection
        self.frameHTML = frameHTML
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "artifact" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let key = ObjectIdentifier(urlSchemeTask)
        let source = source
        let connection = connection
        let frameHTML = frameHTML
        tasks[key] = Task { @MainActor [weak self] in
            let answer: (data: Data, contentType: String, policy: String?)?
            if url.path == ArtifactSandbox.frameURL.path {
                let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value.flatMap(URL.init(string:))
                answer = page.map { (Data(frameHTML($0).utf8), "text/html; charset=utf-8", nil) }
            } else if url.path.hasPrefix("/api/v1/artifact/") {
                switch source {
                case .html(let html):
                    answer = (ArtifactSandbox.framedPage(Data(html.utf8)), "text/html; charset=utf-8", ArtifactSandbox.pageContentSecurityPolicy)
                case .remote(let artifactId):
                    let data = try? await connection.artifactData(id: artifactId, isDownload: false)
                    answer = data.map { (ArtifactSandbox.framedPage($0), "text/html; charset=utf-8", ArtifactSandbox.pageContentSecurityPolicy) }
                }
            } else if url.path.hasPrefix(ArtifactSandbox.kitPath) {
                let name = String(url.path.dropFirst(ArtifactSandbox.kitPath.count))
                answer = (try? await connection.artifactKitData(name: name)).map { ($0.data, $0.contentType, nil) }
            } else {
                answer = nil
            }
            guard let self, self.tasks.removeValue(forKey: key) != nil else { return }
            guard let answer else {
                urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
                return
            }
            var headers = ["Content-Type": answer.contentType, "Cache-Control": "no-store"]
            if let policy = answer.policy { headers["Content-Security-Policy"] = policy }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(answer.data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}

/// ArtifactRows holds what each inline artifact measured and read while the app runs, for the rows a list draws again.
@MainActor
enum ArtifactRows {
    static var memory = ArtifactRowMemory()
}

/// ArtifactCardView is a page, drawing or document the assistant made, shown
/// under the tool line. A tap on the title opens it full size.
struct ArtifactCardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    let artifact: ArtifactReference
    let connection: Connection
    let onOpen: () -> Void

    @State private var height: Double
    @State private var markdown: String?
    /// Whether the card starts at the height this artifact measured before, drawn again as the list scrolls back to it.
    private let isHeightRemembered: Bool

    init(artifact: ArtifactReference, connection: Connection, onOpen: @escaping () -> Void) {
        self.artifact = artifact
        self.connection = connection
        self.onOpen = onOpen
        let remembered = ArtifactRows.memory.height(artifactId: artifact.id)
        isHeightRemembered = remembered != nil
        _height = State(initialValue: remembered ?? ArtifactSandbox.defaultHeight)
        _markdown = State(initialValue: ArtifactRows.memory.text(artifactId: artifact.id))
    }

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
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Open full size"), onOpen)
        .contextMenu {
            Button(action: onOpen) { Label("Open full size", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        .task {
            // The screenshot run opens a page or a document full size, as a tap on its title does.
            guard appModel.isDemo, DemoArtifact.opensFullSize(artifact.kind, screen: DemoOptions.screen) else { return }
            try? await Task.sleep(for: .seconds(1.5))
            onOpen()
        }
    }


    private var pageSource: ArtifactWebView.Source {
        appModel.isDemo ? ArtifactWebView.Source.html(ChatRenderingDemo.artifactText(artifactId: artifact.id) ?? DemoArtifact.html) : ArtifactWebView.Source.remote(artifactId: artifact.id)
    }

    private func loadMarkdown() async -> String? {
        if appModel.isDemo { return ChatRenderingDemo.artifactText(artifactId: artifact.id) ?? DemoArtifact.markdown }
        return try? await connection.artifactText(id: artifact.id)
    }

    @ViewBuilder
    private var content: some View {
        if artifact.kind == .markdown {
            MarkdownView(markdown: markdown ?? "")
                // Until the document has been read once, a steady space stands in for it.
                .frame(minHeight: markdown == nil ? ArtifactSandbox.inlineHeightRange.lowerBound : nil, alignment: .top)
                .frame(maxHeight: 320, alignment: .top)
                .clipped()
                .task(id: artifact.id) {
                    guard markdown == nil, let text = await loadMarkdown() else { return }
                    markdown = text
                    ArtifactRows.memory.remember(text: text, artifactId: artifact.id)
                }
        } else {
            ArtifactWebView(
                source: pageSource, title: artifact.title,
                connection: connection, isDark: colorScheme == .dark, isInline: true, height: $height,
                isHeightRemembered: isHeightRemembered
            )
            .frame(height: height)
            .onChange(of: height) { _, measured in ArtifactRows.memory.remember(height: measured, artifactId: artifact.id) }
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
                        source: pageSource, title: artifact.title,
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
                        .foregroundStyle(Color.statusError)
                        .padding(8)
                }
            }
        }
        .sheet(item: $download) { file in
            FileExporter(url: file.url)
        }
    }


    private var pageSource: ArtifactWebView.Source {
        appModel.isDemo ? ArtifactWebView.Source.html(ChatRenderingDemo.artifactText(artifactId: artifact.id) ?? DemoArtifact.html) : ArtifactWebView.Source.remote(artifactId: artifact.id)
    }

    private func loadMarkdown() async -> String? {
        if appModel.isDemo { return ChatRenderingDemo.artifactText(artifactId: artifact.id) ?? DemoArtifact.markdown }
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
                Text(errorText).font(.footnote).foregroundStyle(Color.statusError)
            }
        }
        .padding(12)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

/// DemoArtifact is an invented page and document for screenshots. The page does what the server's artifact kit does: it takes the
/// theme from its address fragment on load and on every change, hides a heading that repeats the title the app shows, and tells
/// the frame around it how tall it is.
enum DemoArtifact {
    static func opensConversation(screen: String?) -> Bool { screen == "artifact-full" || screen == "artifact-document-full" }

    static func opensFullSize(_ kind: ArtifactReference.Kind, screen: String?) -> Bool {
        (screen == "artifact-full" && kind == .html) || (screen == "artifact-document-full" && kind == .markdown)
    }

    static let markdown = """
        ## Weekly throughput

        Pallets moved by each site, Monday to Sunday.

        | Site | Pallets | Change |
        | :--- | ---: | ---: |
        | site01 | 1,240 | +6% |
        | site02 | 980 | -2% |
        | site03 | 610 | +11% |

        ### What changed

        - **site01** ran a second shift on Thursday and Friday.
        - **site02** lost half a day to a conveyor stop on Tuesday.
        - **site03** added a pick station, which shows from Wednesday on.

        ### Next week

        1. Keep the second shift at site01 if the inbound volume holds.
        2. Check the conveyor at site02 before Monday's first wave.
        3. Compare site03's new station with its others after a full week.

        > Numbers are invented for the demo.
        """

    static let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        :root { --text: #212121; --muted: #666666; --bar: #e76125; --grid: #e0e0e0; }
        :root[data-theme="dark"] { --text: #ffffff; --muted: #b3b3b3; --bar: #ff7025; --grid: #3a3a3a; }
        html, body { margin: 0; background: transparent; color: var(--text); font: 15px -apple-system, system-ui, sans-serif; }
        body { padding: 4px 2px 8px; }
        h1 { font-size: 17px; margin: 0 0 8px; }
        p { color: var(--muted); margin: 0 0 12px; font-size: 13px; }
        svg { display: block; width: 100%; height: auto; }
        .bar { fill: var(--bar); } .label { fill: var(--muted); font-size: 11px; } .grid { stroke: var(--grid); }
        </style></head><body>
        <h1>Weekly pallet throughput</h1>
        <p>Pallets moved per day across the three demo sites.</p>
        <svg viewBox="0 0 320 200" role="img" aria-label="Pallets per day, Monday to Sunday">
          <line class="grid" x1="24" y1="20" x2="316" y2="20"/><line class="grid" x1="24" y1="90" x2="316" y2="90"/><line class="grid" x1="24" y1="160" x2="316" y2="160"/>
          <text class="label" x="0" y="24">600</text><text class="label" x="0" y="94">300</text><text class="label" x="8" y="164">0</text>
          <rect class="bar" x="34" y="62" width="28" height="98" rx="3"/><rect class="bar" x="76" y="48" width="28" height="112" rx="3"/>
          <rect class="bar" x="118" y="70" width="28" height="90" rx="3"/><rect class="bar" x="160" y="34" width="28" height="126" rx="3"/>
          <rect class="bar" x="202" y="28" width="28" height="132" rx="3"/><rect class="bar" x="244" y="104" width="28" height="56" rx="3"/>
          <rect class="bar" x="286" y="122" width="28" height="38" rx="3"/>
          <text class="label" x="38" y="180">Mon</text><text class="label" x="81" y="180">Tue</text><text class="label" x="121" y="180">Wed</text>
          <text class="label" x="165" y="180">Thu</text><text class="label" x="211" y="180">Fri</text><text class="label" x="250" y="180">Sat</text>
          <text class="label" x="291" y="180">Sun</text>
        </svg>
        <script>
        (function () {
          var root = document.documentElement;
          function followTheme() {
            var asked = /theme=(dark|light)/.exec(location.hash || "");
            root.setAttribute("data-theme", asked ? asked[1] : (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"));
          }
          function hideRepeatedTitle() {
            var title = /[#&]title=([^&]*)/.exec(location.hash || "");
            if (!title || window.parent === window) { return; }
            var text = decodeURIComponent(title[1]).trim().toLowerCase();
            document.querySelectorAll("h1, h2, h3").forEach(function (heading) {
              if (heading.textContent.trim().toLowerCase() === text) { heading.hidden = true; }
            });
          }
          function tellHeight() {
            // The body's own height: the root's scroll height is never less than the frame, so a page in a taller frame never shrank.
            var style = getComputedStyle(document.body);
            var height = Math.ceil(document.body.getBoundingClientRect().height + parseFloat(style.marginTop) + parseFloat(style.marginBottom));
            if (window.parent !== window) { window.parent.postMessage({ portalArtifact: { height: height } }, "*"); }
          }
          followTheme();
          hideRepeatedTitle();
          addEventListener("hashchange", followTheme);
          addEventListener("load", tellHeight);
          new ResizeObserver(tellHeight).observe(document.body);
        })();
        </script>
        </body></html>
        """
}
