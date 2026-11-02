import PortalKit
import SwiftUI
import UIKit

/// DemoMenuPresenter carries a menu's items from the `...` button to the page, so a screenshot run, which cannot tap, can
/// show them in a popover under the button.
@Observable
final class DemoMenuPresenter {
    var items: AnyView?
}

extension View {
    /// On the demo screen `screen`, shows the items of the page's `DetailMenu` in a popover at the top right, a moment after the page appears.
    func demoMenuHost(screen: String) -> some View { modifier(DemoMenuHost(screen: screen)) }
}

private struct DemoMenuHost: ViewModifier {
    let screen: String
    @State private var presenter = DemoMenuPresenter()
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .environment(presenter)
            .popover(isPresented: $isShown, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 14) { presenter.items }
                    .buttonStyle(.plain)
                    .padding(20)
                    .presentationCompactAdaptation(.popover)
            }
            .task {
                guard DemoOptions.screen == screen else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                isShown = presenter.items != nil
            }
    }
}

/// DetailMenu is the `...` menu in the trailing toolbar of a detail screen: the
/// place for what is done rarely (copy the link, edit, pause, destroy), so the
/// page itself keeps only what the person comes for.
struct DetailMenu<Content: View>: View {
    var demoScreen: String?
    @ViewBuilder let content: Content
    @Environment(DemoMenuPresenter.self) private var presenter: DemoMenuPresenter?

    init(demoScreen: String? = nil, @ViewBuilder content: () -> Content) {
        self.demoScreen = demoScreen
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("detailMenuButton")
        .onAppear {
            if let demoScreen, DemoOptions.screen == demoScreen { presenter?.items = AnyView(content) }
        }
    }
}

/// LinkMenuItems are "Copy link" and "Share" for a page. The address is the
/// page's address in the Portal web app on the signed-in account's server, so it
/// opens in a browser, and in a chat Portal turns it into a card that opens the
/// page in this app.
struct LinkMenuItems: View {
    @Environment(SessionModel.self) private var session
    let link: PortalLink
    @Binding var isCopied: Bool

    var body: some View {
        let url = link.url(server: session.account.server)
        Button {
            UIPasteboard.general.string = url.absoluteString
            isCopied = true
        } label: {
            Label("Copy link", systemImage: "link")
        }
        ShareLink(item: url) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

extension View {
    /// Says "Link copied" for a moment at the bottom of the screen when `isCopied` turns on, then turns it off.
    func linkCopiedToast(_ isCopied: Binding<Bool>) -> some View {
        modifier(LinkCopiedToast(isCopied: isCopied))
    }
}

private struct LinkCopiedToast: ViewModifier {
    @Binding var isCopied: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isCopied {
                    Label("Link copied", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("linkCopiedToast")
                }
            }
            .animation(.snappy, value: isCopied)
            .sensoryFeedback(.success, trigger: isCopied) { _, isNowCopied in isNowCopied }
            .onChange(of: isCopied) { _, isNowCopied in
                if isNowCopied { AccessibilityNotification.Announcement(String(localized: "Link copied")).post() }
            }
            .task(id: isCopied) {
                guard isCopied else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if !Task.isCancelled { isCopied = false }
            }
    }
}

/// OpenedLink is a page of Portal that a tapped link asked for, shown in a sheet over whatever the person was reading.
struct OpenedLink: Identifiable, Equatable {
    let link: PortalLink
    var id: PortalLink { link }
}

/// LinkedPageSheet opens the screen for a link: it looks the page up (a ticket by its number, a controller by its id),
/// and shows the same screen a list would push, with a Close button. When the page cannot be loaded the web page is offered.
struct LinkedPageSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let link: PortalLink

    private enum Phase {
        case loading
        case loaded(PortalRoute)
        case failed(String)
    }

    @State private var phase = Phase.loading

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView()
                case .loaded(let route):
                    PortalRouteView(route: route)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not open this page", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") { Task { await resolve() } }
                        Button("Open on the web") {
                            let address = link.url(server: session.account.server)
                            dismiss()
                            Task { await appModel.openInApp(address, account: session.account) }
                        }
                    }
                }
            }
            .portalDestinations()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task(id: link) { await resolve() }
    }

    private func resolve() async {
        phase = .loading
        let connection = appModel.connection(for: session.account)
        do {
            switch link {
            case .ticket(let sequence): phase = .loaded(.ticket(id: try await connection.ticket(sequence: sequence).id))
            case .controller(let id): phase = .loaded(.controller(try await connection.controller(id: id)))
            case .virtualController(let id): phase = .loaded(.virtualController(try await connection.virtualController(id: id)))
            case .release(let id): phase = .loaded(.release(id: id))
            }
        } catch {
            appModel.handle(error, account: session.account)
            phase = .failed(error.userMessage)
        }
    }
}
