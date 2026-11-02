import PortalKit
import SwiftUI
import UIKit
import WebKit

/// WebAppsSection is the Apps section of a controller's or a virtual controller's page: a grid of tiles, each an installed web app with
/// its icon and name. A tile opens the app in the built-in browser, signed in the same way as the controller's web UI.
struct WebAppsSection: View {
    /// The row the demo scrolls to.
    static let scrollID = "web-apps"

    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let controllerId: String?
    let virtualControllerId: String?
    /// For a controller, whether its cloud web UI can be signed in to. The apps of an offline controller open there.
    let canOpenCloud: Bool

    private enum Phase {
        case loading
        case loaded(ControllerWebAppList)
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        if session.capabilities.offersControllerWebApps {
            Section("Apps") {
                content
                    .id(Self.scrollID)
                    .task(id: [controllerId ?? "", virtualControllerId ?? ""]) { await load() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            WebAppGrid(apps: Self.placeholders, open: { _ in })
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading"))
        case .loaded(let list):
            if !list.isAvailable || (list.source == "cloud" && !canOpenCloud) {
                note("Apps are not available right now.")
            } else if list.webApps.isEmpty {
                note("No web apps are installed.")
            } else {
                WebAppGrid(apps: list.webApps) { open($0, source: list.source) }
            }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Text("Apps could not be loaded.").font(.footnote).foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
            }
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }

    private static let placeholders: [ControllerWebApp] = (1...4).map { ControllerWebApp(webAppId: "placeholder\($0)", name: "Application") }

    private func load() async {
        let connection = appModel.connection(for: session.account)
        do {
            let list = try await connection.controllerWebApps(controllerId: controllerId, virtualControllerId: controllerId == nil ? virtualControllerId : nil)
            phase = .loaded(list)
            if appModel.isDemo, DemoOptions.screen == "controller-app-open", let first = list.webApps.first {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                open(first, source: list.source)
            }
        } catch {
            // A page that was reloaded keeps the apps it already has.
            guard !Task.isCancelled else { return }
            if case .loaded = phase { return }
            phase = .failed
        }
    }

    private func open(_ app: ControllerWebApp, source: String?) {
        guard let path = app.openPath else { return }
        let server = session.account.server
        let url: URL?
        if let controllerId {
            url = ControllerLinks.appURL(controllerId: controllerId, source: source, openPath: path, server: server)
        } else if let virtualControllerId {
            url = ControllerLinks.virtualAppURL(virtualControllerId: virtualControllerId, openPath: path, server: server)
        } else {
            url = nil
        }
        guard let url else { return }
        let account = session.account
        Task {
            await appModel.openInApp(url, account: account)
            if appModel.isDemo { DemoBrowser.showApp(named: app.displayName, in: appModel, account: account) }
        }
    }
}

/// WebAppGrid lays the tiles out in as many columns as fit, from one on the largest text sizes.
private struct WebAppGrid: View {
    let apps: [ControllerWebApp]
    let open: (ControllerWebApp) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var tileWidth = 84.0
    @ScaledMetric(relativeTo: .caption) private var iconSize = 52.0

    var body: some View {
        TileGridLayout(minimumTileWidth: tileWidth, spacing: 12) {
            ForEach(apps) { app in
                Button { open(app) } label: {
                    VStack(spacing: 6) {
                        WebAppIconView(app: app, size: iconSize)
                        Text(app.displayName)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: app.displayName))
            }
        }
        .padding(.vertical, 4)
    }
}

/// TileGridLayout puts equal-width tiles in rows: as many columns as fit the minimum width, at least one. A row is as tall as its tallest tile.
private struct TileGridLayout: Layout {
    let minimumTileWidth: CGFloat
    let spacing: CGFloat

    private func columnCount(for width: CGFloat) -> Int {
        max(1, Int(((width + spacing) / (minimumTileWidth + spacing)).rounded(.down)))
    }

    private func rowHeights(width: CGFloat, subviews: Subviews) -> (columns: Int, tileWidth: CGFloat, heights: [CGFloat]) {
        let columns = columnCount(for: width)
        let tileWidth = max(1, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let end = min(start + columns, subviews.count)
            heights.append((start..<end).map { subviews[$0].sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }.max() ?? 0)
        }
        return (columns, tileWidth, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumTileWidth
        let rows = rowHeights(width: width, subviews: subviews)
        let height = rows.heights.reduce(0, +) + spacing * CGFloat(max(0, rows.heights.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rowHeights(width: bounds.width, subviews: subviews)
        var originY = bounds.minY
        for (rowIndex, rowHeight) in rows.heights.enumerated() {
            let start = rowIndex * rows.columns
            let end = min(start + rows.columns, subviews.count)
            for index in start..<end {
                let originX = bounds.minX + CGFloat(index - start) * (rows.tileWidth + spacing)
                subviews[index].place(at: CGPoint(x: originX, y: originY), anchor: .topLeading, proposal: ProposedViewSize(width: rows.tileWidth, height: rowHeight))
            }
            originY += rowHeight + spacing
        }
    }
}

/// WebAppIconView is an app's icon on a rounded square, or a generic symbol while it loads, when it has none and when it fails to load.
struct WebAppIconView: View {
    @Environment(SessionModel.self) private var session
    let app: ControllerWebApp
    let size: CGFloat

    @State private var loaded: UIImage?

    var body: some View {
        let subject = app.iconSubject
        let shown = loaded ?? subject.flatMap { session.avatarImages.image(for: $0) }
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(Color(.tertiarySystemFill))
            if let shown {
                Image(uiImage: shown).resizable().scaledToFit().padding(size * 0.1).transition(.opacity)
            } else {
                Image(systemName: "square.grid.2x2").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
        .task(id: subject?.cacheKey) {
            guard let subject else { loaded = nil; return }
            if let held = session.avatarImages.image(for: subject) { loaded = held; return }
            guard let data = await session.avatars.data(for: subject), let image = await WebAppIconDecoder.image(from: data) else { return }
            session.avatarImages.store(image, for: subject)
            withAnimation(.easeOut(duration: 0.15)) { loaded = image }
        }
    }
}

/// WebAppIconDecoder turns an icon's bytes into a picture. A raster image decodes directly; an SVG, which is what most apps ship, is drawn
/// once by WebKit, since UIKit has no SVG decoder.
@MainActor
enum WebAppIconDecoder {
    static func image(from data: Data) async -> UIImage? {
        if let image = UIImage(data: data) { return image }
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        guard head.contains("<svg") else { return nil }
        return await SVGRasterizer.shared.image(from: data)
    }
}

/// SVGRasterizer draws an SVG into a picture with one web view that sits outside the window's visible area. It draws one icon at a time and
/// gives up on a page that does not finish loading, so a broken icon never blocks the next.
@MainActor
final class SVGRasterizer: NSObject, WKNavigationDelegate {
    static let shared = SVGRasterizer()
    private static let side: CGFloat = 192

    private var webView: WKWebView?
    private var loadWaiter: CheckedContinuation<Void, Never>?
    private var loadGeneration = 0
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func image(from data: Data) async -> UIImage? {
        await acquire()
        defer { release() }
        guard let webView = attachedWebView() else { return nil }
        let side = Int(Self.side)
        let html = """
            <!doctype html><html><head><meta name="viewport" content="width=\(side)"><style>
            html, body { margin: 0; background: transparent; }
            img { display: block; width: \(side)px; height: \(side)px; object-fit: contain; }
            </style></head><body><img src="data:image/svg+xml;base64,\(data.base64EncodedString())"></body></html>
            """
        await load(html, in: webView)
        try? await Task.sleep(nanoseconds: 60_000_000)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        configuration.afterScreenUpdates = true
        return try? await webView.takeSnapshot(configuration: configuration)
    }

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    private func attachedWebView() -> WKWebView? {
        if let webView, webView.window != nil { return webView }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: CGRect(x: -2 * Self.side, y: -2 * Self.side, width: Self.side, height: Self.side), configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.navigationDelegate = self
        window.addSubview(view)
        webView = view
        return view
    }

    private func load(_ html: String, in webView: WKWebView) async {
        loadGeneration += 1
        let generation = loadGeneration
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadWaiter = continuation
            webView.loadHTMLString(html, baseURL: nil)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if self?.loadGeneration == generation { self?.finishLoad() }
            }
        }
    }

    private func finishLoad() {
        loadWaiter?.resume()
        loadWaiter = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad() }
}
