import Intents
import PortalKit
import UIKit
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
        if let sender = CommunicationSender(payload: payload, assistantName: NSLocalizedString("Assistant", comment: "")) {
            // A message shows its sender's picture and name; if that cannot be made in time, the plain notification shows.
            Task {
                let shown = await Self.communicationContent(content, sender: sender, payload: payload)
                self.finish(shown)
            }
            return
        }
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
        if let bestAttempt { finish(bestAttempt) }
    }

    /// Hands the content over once, whichever of the work and the time limit comes first.
    private func finish(_ content: UNNotificationContent) {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(content)
    }

    /// The notification as a message from `sender`: an intent donated to the system and applied to the content.
    private static func communicationContent(_ content: UNMutableNotificationContent, sender: CommunicationSender, payload: PushPayload) async -> UNNotificationContent {
        var sender = sender
        var picture: Data?
        let ring = (try? KeychainAccountStore().loadRing()) ?? AccountRing()
        if sender.isAssistant {
            picture = assistantPicture()
        } else if let account = ring.accounts.first(where: { $0.userId == payload.userId }) {
            let connection = SharedConnections().connection(for: account.accountKey)
            if let connection, let chatId = payload.chatId, let room = try? await connection.chat(id: chatId) {
                sender = sender.resolving(members: room.members ?? [])
            }
            if let connection, let subject = sender.avatarSubject {
                let directory = AppGroup.containerURL?.appendingPathComponent("avatars", isDirectory: true).appendingPathComponent(account.accountKey.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined(), isDirectory: true)
                picture = await AvatarStore(connection: connection, directory: directory).data(for: subject)
            }
        }
        let image = INImage(imageData: picture ?? initialsPicture(sender.initials))
        let person = INPerson(
            personHandle: INPersonHandle(value: sender.handle, type: .unknown), nameComponents: nil, displayName: sender.displayName,
            image: image, contactIdentifier: nil, customIdentifier: sender.userId ?? sender.handle)
        let recipient = INPerson(
            personHandle: INPersonHandle(value: payload.userId, type: .unknown), nameComponents: nil, displayName: nil, image: nil,
            contactIdentifier: nil, customIdentifier: payload.userId)
        let intent = INSendMessageIntent(
            recipients: sender.groupName == nil ? nil : [recipient], outgoingMessageType: .outgoingMessageText, content: sender.messageText,
            speakableGroupName: sender.groupName.map { INSpeakableString(spokenPhrase: $0) }, conversationIdentifier: sender.conversationIdentifier,
            serviceName: nil, sender: person, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        try? await interaction.donate()
        return (try? content.updating(from: intent)) ?? content
    }

    /// The letters of a name on a gray circle, for a sender with no picture.
    private static func initialsPicture(_ initials: String) -> Data {
        let size = CGSize(width: 120, height: 120)
        return UIGraphicsImageRenderer(size: size).pngData { _ in
            UIColor.systemGray4.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let text = NSAttributedString(string: initials, attributes: [.font: UIFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: UIColor.secondaryLabel])
            let box = text.size()
            text.draw(at: CGPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2))
        }
    }

    /// The assistant's mark: sparkles on the accent color.
    private static func assistantPicture() -> Data {
        let size = CGSize(width: 120, height: 120)
        return UIGraphicsImageRenderer(size: size).pngData { _ in
            UIColor.systemTeal.withAlphaComponent(0.25).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let symbol = UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .semibold))?.withTintColor(.systemTeal, renderingMode: .alwaysOriginal)
            if let symbol { symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2)) }
        }
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
