import PortalKit
import UIKit
import UserNotifications

/// AppDelegate takes what SwiftUI has no place for: the push token, and the
/// background uploads the share extension started.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var shareBackend: LiveShareBackend?

    private var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !isDemo {
            let backend = LiveShareBackend()
            shareBackend = backend
            // Jobs the extension started and the system finished while the app was not running.
            Task { await backend.resumeAll() }
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == ShareUploader.sessionIdentifier, let shareBackend else { return completionHandler() }
        shareBackend.setFinishEventsHandler(completionHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushDeviceToken.store(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// Asks for permission to notify and registers for push. The token is kept
    /// on the phone until the server has a place to send it.
    static func registerForPush() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}
