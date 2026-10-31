import PortalKit
import UIKit
import UserNotifications

/// AppDelegate takes what SwiftUI has no place for: the push token, a
/// notification's buttons, and the background uploads the share extension
/// started.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var shareBackend: LiveShareBackend?

    private var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !isDemo {
            let backend = LiveShareBackend()
            shareBackend = backend
            // Jobs the extension started and the system finished while the app was not running.
            Task { await backend.resumeAll() }
            UNUserNotificationCenter.current().delegate = self
            Task { await Self.registerCategories() }
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == ShareUploader.sessionIdentifier, let shareBackend else { return completionHandler() }
        shareBackend.setFinishEventsHandler(completionHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushDeviceToken.store(deviceToken)
        Task { await AppModel.shared.registerPushDevices() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// Asks for permission to notify and registers for push. The token goes to
    /// every signed-in account's server when Apple hands it over.
    static func registerForPush() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    // MARK: notification categories

    /// The categories that do not depend on a notification: approve or deny
    /// behind device authentication, and a typed reply. A question's own
    /// category, with a button per choice, is registered by the notification
    /// service extension; both are kept.
    static func registerCategories() async {
        let center = UNUserNotificationCenter.current()
        var categories = await center.notificationCategories()
        categories = categories.filter { $0.identifier != PushCategory.approval && $0.identifier != PushCategory.reply }
        categories.insert(
            UNNotificationCategory(
                identifier: PushCategory.approval,
                actions: [
                    UNNotificationAction(identifier: PushCategory.approveAction, title: String(localized: "Approve"), options: [.authenticationRequired]),
                    UNNotificationAction(identifier: PushCategory.denyAction, title: String(localized: "Deny"), options: [.authenticationRequired, .destructive]),
                ], intentIdentifiers: [], options: []))
        categories.insert(
            UNNotificationCategory(
                identifier: PushCategory.reply,
                actions: [
                    UNTextInputNotificationAction(
                        identifier: PushCategory.replyAction, title: String(localized: "Reply"), options: [],
                        textInputButtonTitle: String(localized: "Send"), textInputPlaceholder: String(localized: "Message"))
                ], intentIdentifiers: [], options: []))
        center.setNotificationCategories(categories)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let actionIdentifier = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        guard let payload = PushPayload(userInfo: response.notification.request.content.userInfo) else { return }
        await Self.handle(payload: payload, actionIdentifier: actionIdentifier, text: text)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let payload = PushPayload(userInfo: notification.request.content.userInfo) else { return [.banner, .list, .sound] }
        return await AppModel.shared.presentation(for: payload)
    }

    @MainActor
    private static func handle(payload: PushPayload, actionIdentifier: String, text: String?) async {
        let model = AppModel.shared
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            model.open(payload)
        case UNNotificationDismissActionIdentifier:
            return
        default:
            if let action = payload.action(forButton: actionIdentifier, text: text) {
                await model.perform(action, for: payload)
            } else {
                model.open(payload)
            }
        }
    }
}
