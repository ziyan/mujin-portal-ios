import UserNotifications

/// NotificationService is where a push notification is changed before iOS
/// shows it. Push arrives in a later phase, so for now it shows the
/// notification as it came.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        contentHandler(request.content)
    }

    override func serviceExtensionTimeWillExpire() {}
}
