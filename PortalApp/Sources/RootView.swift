import PortalKit
import SwiftUI
import UIKit

/// AppRoot shows the real app, or the demo a person entered from the welcome screen in its place.
struct AppRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let demo = model.demoModel {
            // The strip takes its own space above the whole app, so every screen's navigation bar starts below it.
            VStack(spacing: 0) {
                DemoBanner(exit: demo.exitDemo)
                RootView()
                    .environment(demo)
                    .id(ObjectIdentifier(demo))
            }
        } else {
            RootView()
        }
    }
}

/// DemoBanner marks a demo entered from the welcome screen and offers the way out.
struct DemoBanner: View {
    let exit: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text("Demo")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
            Text("Nothing here is real.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let exit {
                Button("Exit demo", action: exit)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("exitDemoButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar, ignoresSafeAreaEdges: .top)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isDemo, let screen = ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"], screen.hasPrefix("share") {
                DemoShare.view(ticket: screen == "share-ticket")
            } else if let account = model.activeAccount {
                MainTabsView(account: account)
                    .id(account.accountKey)
            } else {
                SignInView(isAddingAccount: false)
            }
        }
        .task(id: model.activeAccount?.accountKey) {
            if model.isDemo, ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "browser", let account = model.activeAccount {
                DemoBrowser.show(in: model, account: account)
            }
            guard !model.isDemo, model.activeAccount != nil else { return }
            await AppDelegate.registerForPush()
            // At every launch, since the token can change and registering is idempotent.
            await model.registerPushDevices()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in model.scenePhaseChanged(isActive: phase == .active) }
        .onChange(of: model.activeAccount?.accountKey) { _, _ in model.scenePhaseChanged(isActive: scenePhase == .active) }
        .background(TouchActivityProbe { model.touched() })
        .environment(\.openURL, OpenURLAction { url in model.handleLink(url) })
        .fullScreenCover(item: $model.presentedWeb) { session in
            WebBrowserView(session: session) { model.presentedWeb = nil }
        }
        .sheet(item: Binding(get: { model.openedCitation.map(IdentifiableCitation.init) }, set: { model.openedCitation = $0?.citation })) { item in
            MemoryCitationSheet(citation: item.citation)
                .environment(model)
        }
        .fullScreenCover(item: $model.safariPage) { page in
            if model.isDemo {
                DemoSafariPage(url: page.url)
            } else {
                SafariView(url: page.url).ignoresSafeArea()
            }
        }
        .alert(
            "Signed out", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(model.notice ?? "") })
    }
}

/// TouchActivityProbe tells the app when the person last touched the screen,
/// for the idle time in the presence report. It watches touches without
/// taking them from anything.
struct TouchActivityProbe: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) { view.onTouch = onTouch }

    final class ProbeView: UIView {
        var onTouch: (() -> Void)?
        private var recognizer: TouchObserver?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            guard let window else { return }
            let observer = TouchObserver { [weak self] in self?.onTouch?() }
            window.addGestureRecognizer(observer)
            recognizer = observer
        }
    }

    final class TouchObserver: UIGestureRecognizer {
        private let onTouch: () -> Void

        init(onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouch()
            state = .failed
        }
    }
}

/// IdentifiableCitation lets a citation be the item of a sheet.
struct IdentifiableCitation: Identifiable {
    let citation: MemoryCitation
    var id: String { citation.label }
}
