import PortalKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isDemo, let screen = ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"], screen.hasPrefix("share") {
                DemoShare.view(ticket: screen == "share-ticket")
            } else if let account = model.activeAccount {
                ConversationListView(account: account)
                    .id(account.accountKey)
            } else {
                SignInView(isAddingAccount: false)
            }
        }
        .task(id: model.activeAccount?.accountKey) {
            if model.isDemo, ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "browser", let account = model.activeAccount {
                DemoBrowser.show(in: model, account: account)
            }
            guard !model.isDemo, let account = model.activeAccount else { return }
            await AppDelegate.registerForPush()
            // The server must offer a place to register the token before the app sends it.
            model.isPushRegistrationOffered = await model.connection(for: account).offersMutation("registerPushDevice")
        }
        .environment(\.openURL, OpenURLAction { url in model.handleLink(url) })
        .fullScreenCover(item: $model.presentedWeb) { session in
            WebBrowserView(session: session) { model.presentedWeb = nil }
        }
        .fullScreenCover(item: $model.safariPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .alert(
            "Signed out", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(model.notice ?? "") })
    }
}
