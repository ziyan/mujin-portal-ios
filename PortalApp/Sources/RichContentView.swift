import PortalKit
import SwiftUI
import WebKit

/// RichContentPage draws what text cannot: a Mermaid diagram, a formula on its own line, or a paragraph that holds formulas, with the
/// Mermaid and KaTeX the app carries. Each drawing is a small web view with a private, empty data store and no network: the page,
/// the libraries and their fonts come from the app's own scheme, every other address is blocked, the diagram runs under Mermaid's
/// strict security level, and the only message the page can send is its height, or that it could not draw.
enum RichContentPage {
    static let scheme = "portal-rich"
    static let pageURL = URL(string: "\(scheme)://content/page.html")!
    private static let folder = Bundle.main.url(forResource: "RichContent", withExtension: nil)

    enum Content: Equatable {
        case diagram(String)
        case formula(String)
        case paragraph(html: String)
    }

    /// A library file or font, by its path under the app's scheme.
    static func file(path: String) -> (data: Data, contentType: String)? {
        guard let folder, !path.contains("..") else { return nil }
        let url = folder.appendingPathComponent(String(path.drop { $0 == "/" }))
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type: String = switch url.pathExtension {
        case "js": "text/javascript"
        case "css": "text/css"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
        return (data, type)
    }

    static func html(_ content: Content) -> String {
        let source: String
        let kind: String
        switch content {
        case .diagram(let text):
            source = text
            kind = "diagram"
        case .formula(let tex):
            source = tex
            kind = "formula"
        case .paragraph(let html):
            source = html
            kind = "paragraph"
        }
        let quoted = (try? String(data: JSONSerialization.data(withJSONObject: [source]), encoding: .utf8)) ?? "[\"\"]"
        return """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' \(scheme):; style-src 'unsafe-inline' \(scheme):; font-src \(scheme):; img-src data:">
            <link rel="stylesheet" href="katex.min.css">
            <style>
            :root { color-scheme: light dark; }
            html, body { margin: 0; padding: 0; background: transparent; color: -apple-system-label; font: -apple-system-body; overflow: hidden; }
            #content { padding: 2px 0; overflow-wrap: anywhere; }
            #content.diagram { padding: 8px; text-align: center; }
            #content.formula { text-align: center; overflow-x: auto; }
            #content svg { max-width: 100%; height: auto; }
            code { font: -apple-system-footnote; font-family: ui-monospace, Menlo, monospace; }
            .katex { font-size: 1.05em; }
            </style>
            <script src="katex.min.js"></script>
            \(kind == "diagram" ? "<script src=\"mermaid.min.js\"></script>" : "")
            </head><body><div id="content" class="\(kind)"></div>
            <script>
            (function () {
              var source = \(quoted)[0];
              var kind = "\(kind)";
              var box = document.getElementById("content");
              function tell(message) { window.webkit.messageHandlers.richContent.postMessage(message); }
              function tellHeight() { tell({ height: Math.ceil(document.documentElement.scrollHeight) }); }
              function fail() { tell({ failed: true }); }
              try {
                if (kind === "formula") {
                  katex.render(source, box, { displayMode: true, throwOnError: true, trust: false });
                  tellHeight();
                } else if (kind === "paragraph") {
                  box.innerHTML = source;
                  var spans = box.querySelectorAll("span.tex");
                  for (var index = 0; index < spans.length; index++) {
                    var span = spans[index];
                    katex.render(span.textContent, span, { displayMode: span.classList.contains("display"), throwOnError: true, trust: false });
                  }
                  tellHeight();
                } else {
                  var isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
                  mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: isDark ? "dark" : "default" });
                  mermaid.render("diagram", source).then(function (result) {
                    box.innerHTML = result.svg;
                    tellHeight();
                  }, fail);
                }
              } catch (error) {
                fail();
              }
              new ResizeObserver(tellHeight).observe(document.documentElement);
            })();
            </script></body></html>
            """
    }

    /// A WebKit content rule list that blocks every address but the drawing's own scheme.
    static let contentRuleListJSON = """
        [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^\(scheme)://content/"},"action":{"type":"ignore-previous-rules"}}]
        """
}

/// RichContentSchemeHandler serves one drawing's page and the bundled libraries and fonts.
@MainActor
final class RichContentSchemeHandler: NSObject, WKURLSchemeHandler {
    private let page: String

    init(page: String) {
        self.page = page
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "content" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let answer: (data: Data, contentType: String)? =
            url.path == RichContentPage.pageURL.path ? (Data(page.utf8), "text/html; charset=utf-8") : RichContentPage.file(path: url.path)
        guard let answer else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": answer.contentType])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(answer.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

/// RichContentWebView is one drawing, as tall as it says it is.
private struct RichContentWebView: UIViewRepresentable {
    let content: RichContentPage.Content
    @Binding var height: CGFloat
    @Binding var hasFailed: Bool
    /// Called with a picture of the drawing once it has drawn and kept its height a moment.
    let onDrawn: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, hasFailed: $hasFailed, onDrawn: onDrawn) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(RichContentSchemeHandler(page: RichContentPage.html(content)), forURLScheme: RichContentPage.scheme)
        configuration.userContentController.add(context.coordinator, name: "richContent")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        Task {
            if let list = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "rich-content", encodedContentRuleList: RichContentPage.contentRuleListJSON)
            {
                webView.configuration.userContentController.add(list)
                webView.load(URLRequest(url: RichContentPage.pageURL))
            } else {
                hasFailed = true
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "richContent")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let height: Binding<CGFloat>
        private let hasFailed: Binding<Bool>
        private let onDrawn: (UIImage) -> Void
        weak var webView: WKWebView?
        private var snapshotTask: Task<Void, Never>?

        init(height: Binding<CGFloat>, hasFailed: Binding<Bool>, onDrawn: @escaping (UIImage) -> Void) {
            self.height = height
            self.hasFailed = hasFailed
            self.onDrawn = onDrawn
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            if body["failed"] as? Bool == true {
                snapshotTask?.cancel()
                hasFailed.wrappedValue = true
            } else if let reported = (body["height"] as? NSNumber)?.doubleValue, reported > 0 {
                let fitted = min(CGFloat(reported), 2_000)
                if abs(fitted - height.wrappedValue) > 1 { height.wrappedValue = fitted }
                takeSnapshotWhenSettled()
            }
        }

        /// A drawing that has kept its height for a moment is pictured, and the picture stands in for the web view from then on, so a
        /// long chat holds pictures rather than web views and a drawing never draws again as it scrolls.
        private func takeSnapshotWhenSettled() {
            snapshotTask?.cancel()
            snapshotTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, let webView = self.webView, webView.bounds.height > 1 else { return }
                let configuration = WKSnapshotConfiguration()
                configuration.rect = webView.bounds
                configuration.afterScreenUpdates = true
                guard let image = try? await webView.takeSnapshot(configuration: configuration), !Task.isCancelled else { return }
                self.onDrawn(image)
            }
        }

        /// The page loads once; nothing in it opens anything.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url == RichContentPage.pageURL ? .allow : .cancel
        }
    }
}

/// RichDrawingCache keeps the pictures of drawings already made, by what was drawn, in which appearance and at which width, so a
/// drawing that scrolls away and back, or a screen that opens again, shows its picture at once with no web view.
enum RichDrawingCache {
    nonisolated(unsafe) static let pictures: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func key(_ content: RichContentPage.Content, isDark: Bool, width: CGFloat) -> NSString {
        "\(isDark ? "dark" : "light")|\(Int(width.rounded()))|\(String(describing: content).hashValue)|\(String(describing: content).count)" as NSString
    }
}

/// RichDrawing is a drawing with its source to fall back on: until it is drawn the source is not shown, and if it cannot be drawn
/// the source is what shows, never a blank. Once drawn, a picture of it takes the web view's place.
struct RichDrawing<Fallback: View>: View {
    let content: RichContentPage.Content
    let identifier: String
    @ViewBuilder let fallback: () -> Fallback

    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 0
    @State private var hasFailed = false
    @State private var width: CGFloat = 0
    @State private var picture: UIImage?
    /// Whether the drawing has come near the screen. A long chat makes its web views one at a time as they come into view, not all
    /// at once when it opens.
    @State private var hasComeIntoView = false

    private var key: NSString { RichDrawingCache.key(content, isDark: colorScheme == .dark, width: width) }

    var body: some View {
        Group {
            if hasFailed {
                fallback()
            } else if let shown = picture ?? (width > 0 ? RichDrawingCache.pictures.object(forKey: key) : nil) {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel(Text(accessibilityText))
                    .accessibilityIdentifier(identifier)
            } else if width > 0, hasComeIntoView {
                RichContentWebView(content: content, height: $height, hasFailed: $hasFailed) { image in
                    RichDrawingCache.pictures.setObject(image, forKey: key)
                    picture = image
                }
                .frame(height: max(height, 24))
                .accessibilityIdentifier(height > 0 ? identifier : "\(identifier)Pending")
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
            if isVisible { hasComeIntoView = true }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            if abs(newWidth - width) > 1 { width = newWidth }
        }
        // A new appearance or width draws again, from the picture made for it if there is one.
        .onChange(of: key) { _, _ in picture = nil }
    }

    /// What VoiceOver reads for the picture: the formula's source, or what the diagram is.
    private var accessibilityText: String {
        switch content {
        case .formula(let tex): tex
        case .diagram: String(localized: "Diagram")
        case .paragraph(let html): html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
    }
}

/// CodeFrame is a code block's frame: a tinted header with the language, small and muted, and a copy button, over its body, a
/// diagram's included. It matches a table's frame.
struct CodeFrame<Body: View>: View {
    let language: String
    let source: String
    @ViewBuilder let content: () -> Body
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: language.split(separator: " ").first.map(String.init) ?? "")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = source
                    isCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        isCopied = false
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, minHeight: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCopied ? Text("Copied") : Text("Copy"))
                .accessibilityIdentifier("codeCopyButton")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .background(Color.gray.opacity(0.10))
            Rectangle().fill(Color.gray.opacity(0.28)).frame(height: 1)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.gray.opacity(0.28), lineWidth: 1))
    }
}

/// InlineFormulaRenderer draws formulas that sit inside a line of words. One hidden web view, sandboxed as the drawings are, draws
/// them one at a time with KaTeX and pictures each, cropped to the formula, with how far it reaches below the baseline. The pictures
/// are kept, by formula, appearance and text size, and a paragraph puts them in its own text, so the words around them stay text.
@MainActor
@Observable
final class InlineFormulaRenderer {
    static let shared = InlineFormulaRenderer()

    struct Picture {
        let image: UIImage
        /// How far the formula reaches below the baseline, in points.
        let descent: CGFloat
    }

    /// Bumped each time a picture is ready, so the paragraphs waiting for it draw again.
    private(set) var version = 0
    @ObservationIgnored private var pictures: [String: Picture] = [:]
    @ObservationIgnored private var failures: Set<String> = []
    @ObservationIgnored private var queue: [(key: String, tex: String, isDark: Bool, fontSize: CGFloat)] = []
    @ObservationIgnored private var isWorking = false
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var isPageReady = false

    static func key(tex: String, isDark: Bool, fontSize: CGFloat) -> String { "\(isDark ? "dark" : "light")|\(Int(fontSize * 10))|\(tex)" }

    func picture(tex: String, isDark: Bool, fontSize: CGFloat) -> Picture? {
        pictures[Self.key(tex: tex, isDark: isDark, fontSize: fontSize)]
    }

    func hasFailed(tex: String, isDark: Bool, fontSize: CGFloat) -> Bool {
        failures.contains(Self.key(tex: tex, isDark: isDark, fontSize: fontSize))
    }

    /// Asks for a formula's picture; the paragraph draws again when it is ready.
    func request(tex: String, isDark: Bool, fontSize: CGFloat) {
        let key = Self.key(tex: tex, isDark: isDark, fontSize: fontSize)
        guard pictures[key] == nil, !failures.contains(key), !queue.contains(where: { $0.key == key }) else { return }
        queue.append((key, tex, isDark, fontSize))
        Task { await work() }
    }

    private func work() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard let webView = await readyWebView() else {
                failures.insert(next.key)
                continue
            }
            webView.overrideUserInterfaceStyle = next.isDark ? .dark : .light
            let measured = try? await webView.callAsyncJavaScript(
                "return window.drawFormula(tex, size)", arguments: ["tex": next.tex, "size": Double(next.fontSize)], contentWorld: .page)
            guard let box = measured as? [String: Any], let width = (box["width"] as? NSNumber)?.doubleValue,
                let height = (box["height"] as? NSNumber)?.doubleValue, let baseline = (box["baseline"] as? NSNumber)?.doubleValue, width > 0, height > 0
            else {
                failures.insert(next.key)
                version += 1
                continue
            }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: ceil(width), height: ceil(height))
            configuration.afterScreenUpdates = true
            if let image = try? await webView.takeSnapshot(configuration: configuration) {
                pictures[next.key] = Picture(image: image, descent: max(0, CGFloat(height - baseline)))
            } else {
                failures.insert(next.key)
            }
            version += 1
        }
    }

    /// The hidden web view, in the window so it draws, out of sight and out of reach.
    private func readyWebView() async -> WKWebView? {
        if let webView, isPageReady { return webView }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)
        else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(RichContentSchemeHandler(page: Self.page), forURLScheme: RichContentPage.scheme)
        guard let list = try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "rich-content", encodedContentRuleList: RichContentPage.contentRuleListJSON)
        else { return nil }
        configuration.userContentController.add(list)
        let created = WKWebView(frame: CGRect(x: -4_000, y: 0, width: 1_200, height: 400), configuration: configuration)
        created.isOpaque = false
        created.backgroundColor = .clear
        created.isUserInteractionEnabled = false
        created.accessibilityElementsHidden = true
        window.addSubview(created)
        webView = created
        created.load(URLRequest(url: RichContentPage.pageURL))
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if (try? await created.evaluateJavaScript("typeof window.drawFormula === 'function' && typeof katex !== 'undefined'")) as? Bool == true {
                isPageReady = true
                return created
            }
        }
        return nil
    }

    private static let page = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' \(RichContentPage.scheme):; style-src 'unsafe-inline' \(RichContentPage.scheme):; font-src \(RichContentPage.scheme):">
        <link rel="stylesheet" href="katex.min.css">
        <style>
        :root { color-scheme: light dark; }
        html, body { margin: 0; padding: 0; background: transparent; color: -apple-system-label; }
        #formula { position: absolute; left: 0; top: 0; white-space: nowrap; line-height: 1; }
        #marker { display: inline-block; width: 0; height: 0; vertical-align: baseline; }
        </style>
        <script src="katex.min.js"></script>
        </head><body><span id="formula"></span>
        <script>
        window.drawFormula = function (tex, size) {
          var box = document.getElementById("formula");
          box.style.fontSize = size + "px";
          katex.render(tex, box, { displayMode: false, throwOnError: true, trust: false });
          var marker = document.createElement("span");
          marker.id = "marker";
          box.appendChild(marker);
          var rect = box.getBoundingClientRect();
          var baseline = marker.getBoundingClientRect().bottom - rect.top;
          return { width: rect.width, height: rect.height, baseline: baseline };
        };
        </script></body></html>
        """
}

/// InlineMathText is a paragraph whose formulas sit in its words: the words stay text, with their links and selection, and each formula
/// is its picture, on the baseline and sized to the text. A formula not drawn yet, or that cannot be, shows as its source in code.
struct InlineMathText: View {
    let text: String
    /// The words as the paragraph shows them, with their links and mentions.
    let words: (String) -> AttributedString
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 17
    private let renderer = InlineFormulaRenderer.shared

    var body: some View {
        let pieces = RichMath.pieces(of: text)
        let isDark = colorScheme == .dark
        _ = renderer.version
        let formulas = pieces.compactMap { piece -> String? in
            if case .formula(let tex, _) = piece { return tex }
            return nil
        }
        let isDrawn = formulas.allSatisfy { renderer.picture(tex: $0, isDark: isDark, fontSize: fontSize) != nil }
        return pieces.reduce(Text(verbatim: "")) { line, piece in
            switch piece {
            case .text(let wordsText):
                return line + Text(words(wordsText))
            case .formula(let tex, _):
                if let picture = renderer.picture(tex: tex, isDark: isDark, fontSize: fontSize) {
                    return line + Text(Image(uiImage: picture.image)).baselineOffset(-picture.descent)
                }
                return line + Text(MarkdownView.inline("`\(tex)`"))
            }
        }
        .accessibilityLabel(Text(spokenText(pieces)))
        .accessibilityIdentifier(isDrawn ? "mathParagraph" : "mathParagraphPending")
        .task(id: "\(isDark)|\(fontSize)|\(text)") {
            for tex in formulas { renderer.request(tex: tex, isDark: isDark, fontSize: fontSize) }
        }
    }

    /// What VoiceOver reads: the words, with each formula's source where it stands.
    private func spokenText(_ pieces: [RichMath.Piece]) -> String {
        pieces.map { piece in
            switch piece {
            case .text(let wordsText): String(words(wordsText).characters)
            case .formula(let tex, _): tex
            }
        }.joined()
    }
}
