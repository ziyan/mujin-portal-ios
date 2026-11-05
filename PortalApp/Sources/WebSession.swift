import Observation
import PortalKit
import SwiftUI
import UIKit
import WebKit

/// WebSession is the built-in browser for one account: a web view whose
/// cookies live in a data store of that account alone. It is kept after the
/// screen closes so the page is still there when the person comes back.
@MainActor
@Observable
final class WebSession: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    let accountKey: String
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var progress = 0.0
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// Which machine and which of its web UIs is open, for the header; nil for any other page.
    private(set) var target: BrowserTarget?
    /// A downloaded file waiting to be saved to Files.
    var downloadedFile: ExportedFile?

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// The Portal host, whose login page means the web session has ended.
    @ObservationIgnored var portalHost: String?
    /// Asks for a new one-time address for a page, or nil when the server will not give one.
    @ObservationIgnored var renewHandoff: (@MainActor (URL) async -> URL?)?
    /// The page the person asked for, and whether its address was already renewed once.
    @ObservationIgnored private var intendedTarget: URL?
    @ObservationIgnored private var hasRenewed = false

    struct ExportedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    init(accountKey: String, dataStoreId: UUID?, contentMode: WKWebpagePreferences.ContentMode? = nil) {
        self.accountKey = accountKey
        let configuration = WKWebViewConfiguration()
        // Cookies are kept per account: a store named by the account's own id.
        // The demo has no account to keep them for.
        configuration.websiteDataStore = dataStoreId.map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        // Controller web UIs are desktop web apps: ask for the desktop site on iPad.
        configuration.defaultWebpagePreferences.preferredContentMode = contentMode ?? (UIDevice.current.userInterfaceIdiom == .pad ? .desktop : .recommended)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.title = view.title ?? "" }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.url = view.url }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.progress = view.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
        ]
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Clears the web view before a new page is shown, so the last page (the live UI, say) is never on screen
    /// while the next one (the cloud UI) is still being asked for.
    func reset(for target: BrowserTarget?) {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        self.target = target
    }

    /// Opens a page through a one-time address that signs the web view in
    /// first, or as it is when the server gave none.
    func open(target: URL, handoff: URL?) {
        intendedTarget = target
        hasRenewed = false
        load(handoff ?? target)
    }

    func loadHTML(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Stops the page and lets go of the web view, before the account's data store is deleted.
    func tearDown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        observations = []
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        let scheme = url.scheme?.lowercased() ?? ""
        // The session ended (12 hours at most, or the grant was revoked): the
        // page lands on Portal's login. Ask for a new address once and go on.
        if navigationAction.targetFrame?.isMainFrame ?? true, let portalHost, url.host?.lowercased() == portalHost, url.path.hasPrefix("/login"),
            let intendedTarget, !hasRenewed, let renewHandoff
        {
            hasRenewed = true
            if let fresh = await renewHandoff(intendedTarget) {
                load(fresh)
                return .cancel
            }
        }
        if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "blob" || scheme == "data" { return .allow }
        // Mail, phone and other app links go to the system.
        await UIApplication.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") { return .download }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKUIDelegate

    /// A link that asks for a new window opens in this one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("web-downloads-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = suggestedFilename.replacingOccurrences(of: "/", with: "-")
        let destination = folder.appendingPathComponent(name.isEmpty ? "download" : name)
        downloadDestinations[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
            downloadedFile = ExportedFile(url: destination)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }

    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]
}

/// WebViewHost shows a session's web view.
struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// FileExporter lets the person save a downloaded file to Files.
struct FileExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}

/// The built-in browser screen: back, forward, reload, share, open in
/// Safari, the page's title and its progress, and a close button.
struct WebBrowserView: View {
    let session: WebSession
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            WebViewHost(webView: session.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if session.isLoading {
                        ProgressView(value: session.progress)
                            .progressViewStyle(.linear)
                    }
                }
                .navigationTitle(session.target?.title ?? (session.title.isEmpty ? (session.url?.host ?? "") : session.title))
                .navigationSubtitle(session.target?.subtitle ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                            .accessibilityIdentifier("webBrowserClose")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if let url = session.url {
                            ShareLink(item: url)
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { session.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                            .disabled(!session.canGoBack)
                        Button { session.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                            .disabled(!session.canGoForward)
                        Spacer()
                        if session.isLoading {
                            Button { session.stopLoading() } label: { Label("Stop", systemImage: "xmark") }
                        } else {
                            Button { session.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        }
                        Spacer()
                        Button {
                            if let url = session.url { UIApplication.shared.open(url) }
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                        }
                        .disabled(session.url == nil)
                    }
                }
        }
        .sheet(item: Binding(get: { session.downloadedFile }, set: { session.downloadedFile = $0 })) { file in
            FileExporter(url: file.url)
        }
    }
}
