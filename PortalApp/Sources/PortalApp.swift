import PortalKit
import SwiftUI

@main
struct PortalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    init() {
        // On iOS 26 the search field's own glass fill appears only after a page has finished sliding in
        // or out, so during the slide it showed just a magnifier and the prompt. A fill of its own, the
        // color the glass settles to, is there from the first frame and the glass replaces it later.
        UISearchTextField.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).backgroundColor = UIColor(named: "SearchFieldFill")
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(model)
                .onOpenURL { url in model.handleIncoming(url) }
        }
    }
}
