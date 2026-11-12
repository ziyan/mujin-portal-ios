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

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, hasFailed: $hasFailed) }

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

        init(height: Binding<CGFloat>, hasFailed: Binding<Bool>) {
            self.height = height
            self.hasFailed = hasFailed
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            if body["failed"] as? Bool == true {
                hasFailed.wrappedValue = true
            } else if let reported = (body["height"] as? NSNumber)?.doubleValue, reported > 0 {
                let fitted = min(CGFloat(reported), 2_000)
                if abs(fitted - height.wrappedValue) > 1 { height.wrappedValue = fitted }
            }
        }

        /// The page loads once; nothing in it opens anything.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url == RichContentPage.pageURL ? .allow : .cancel
        }
    }
}

/// RichDrawing is a drawing with its source to fall back on: until it is drawn the source is not shown, and if it cannot be drawn
/// the source is what shows, never a blank.
struct RichDrawing<Fallback: View>: View {
    let content: RichContentPage.Content
    let identifier: String
    @ViewBuilder let fallback: () -> Fallback

    @State private var height: CGFloat = 0
    @State private var hasFailed = false

    var body: some View {
        if hasFailed {
            fallback()
        } else {
            RichContentWebView(content: content, height: $height, hasFailed: $hasFailed)
                .frame(height: max(height, 24))
                .accessibilityIdentifier(height > 0 ? identifier : "\(identifier)Pending")
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
