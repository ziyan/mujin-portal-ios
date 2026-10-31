import PortalKit
import SwiftUI

@main
struct PortalApp: App {
    @State private var model = AppModel.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
