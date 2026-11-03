import PortalKit
import SwiftUI

@main
struct PortalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(model)
                .onOpenURL { url in model.handleIncoming(url) }
        }
    }
}
