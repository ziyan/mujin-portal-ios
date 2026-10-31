import PortalKit
import UserNotifications

/// NotificationService is where a push notification is changed before iOS
/// shows it. It gives a question its own category, with a button per choice
/// and a typed reply; gives an approval its Approve and Deny buttons; stacks
/// a notification with its conversation; and, for the passive push that
/// replaces a card answered somewhere else, clears the original.
final class NotificationService: UNNotificationServiceExtension {
    /// How many questions' categories are kept. A category is only needed
    /// while its notification can still be shown.
    private static let maximumQuestionCategories = 30
    private static let questionCategoriesKey = "questionCategoryIdentifiers"

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
            let payload = PushPayload(userInfo: request.content.userInfo)
        else {
            contentHandler(request.content)
            return
        }
        bestAttempt = content
        if content.threadIdentifier.isEmpty, let thread = payload.resolvedThreadId { content.threadIdentifier = thread }
        let center = UNUserNotificationCenter.current()

        if payload.isAnswered {
            // The original shares a collapse id with this one and is replaced
            // by it; delivered copies from before are removed too.
            center.getDeliveredNotifications { delivered in
                let identifiers = delivered.compactMap { notification -> String? in
                    guard notification.request.identifier != request.identifier,
                        PushPayload(userInfo: notification.request.content.userInfo)?.interactionId == payload.interactionId
                    else { return nil }
                    return notification.request.identifier
                }
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
                contentHandler(content)
            }
            return
        }

        guard let category = payload.categoryIdentifier else {
            contentHandler(content)
            return
        }
        content.categoryIdentifier = category
        if payload.isQuestion, let interactionId = payload.interactionId {
            // The category must be registered before the notification shows.
            center.getNotificationCategories { existing in
                var categories = existing
                categories.insert(Self.questionCategory(identifier: category, payload: payload))
                categories = Self.pruned(categories, keeping: category, interactionId: interactionId)
                center.setNotificationCategories(categories)
                contentHandler(content)
            }
        } else {
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt { contentHandler(bestAttempt) }
    }

    /// A button per choice, then a typed reply for any other answer.
    private static func questionCategory(identifier: String, payload: PushPayload) -> UNNotificationCategory {
        var actions: [UNNotificationAction] = payload.choices.enumerated().map { index, choice in
            UNNotificationAction(identifier: PushCategory.choiceAction(index: index), title: choice, options: [])
        }
        actions.append(
            UNTextInputNotificationAction(
                identifier: PushCategory.replyAction, title: NSLocalizedString("Reply", comment: ""), options: [],
                textInputButtonTitle: NSLocalizedString("Send", comment: ""), textInputPlaceholder: NSLocalizedString("Your answer", comment: "")))
        return UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [], options: [])
    }

    /// Drops the oldest question categories beyond the ones kept.
    private static func pruned(_ categories: Set<UNNotificationCategory>, keeping identifier: String, interactionId: String) -> Set<UNNotificationCategory> {
        let defaults = AppGroup.defaults
        var recent = (defaults.stringArray(forKey: questionCategoriesKey) ?? []).filter { $0 != identifier }
        recent.append(identifier)
        let kept = Set(recent.suffix(maximumQuestionCategories))
        defaults.set(Array(recent.suffix(maximumQuestionCategories)), forKey: questionCategoriesKey)
        let questionPrefix = PushCategory.question + "."
        return categories.filter { !$0.identifier.hasPrefix(questionPrefix) || kept.contains($0.identifier) }
    }
}
