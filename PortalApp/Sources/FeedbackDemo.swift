import Foundation
import PortalKit

/// FeedbackDemo is the demo's screens for feedback about Portal itself, served only on their own screens against a server that says
/// it has the feature. Every other screen is shot against a server that does not, which is how the app learns to show nothing. All
/// the words are invented.
enum FeedbackDemo {
    /// The screens whose server offers feedback. A screenshot is posted for the ones that open on a tab, as if the person took one.
    static let screens: Set<String> = [
        "feedback-drawer", "feedback-drawer-error", "feedback-drawer-off", "feedback-in-call", "feedback-form", "feedback-list",
        "feedback-tickets", "feedback-ticket", "feedback-list-empty", "feedback-list-error", "feedback-form-open",
    ]

    static func owns(_ screen: String?) -> Bool { screen.map { screens.contains($0) } ?? false }

    /// The screen that opens the thread of a feedback ticket on the Tickets tab.
    static let ticketScreen = "feedback-ticket"
    static let ticketId = "feedback01"

    static func section(for screen: String?) -> AppSection {
        screen?.hasPrefix("feedback-form") == true || screen?.hasPrefix("feedback-list") == true ? .more : .tickets
    }

    /// Whether the demo posts the system's screenshot notification a moment after the tab opens, the way iOS does when the person
    /// takes a screenshot. A test cannot press the side buttons, and the notification is what the app listens for.
    static func postsScreenshot(_ screen: String?) -> Bool {
        ["feedback-drawer", "feedback-drawer-error", "feedback-drawer-off", "feedback-in-call"].contains(screen ?? "")
    }

    /// Whether the first send is refused, to show that the words and the picture are kept.
    static func failsFirstSend(_ screen: String?) -> Bool { screen == "feedback-drawer-error" }

    static let failureMessage = "Feedback could not be saved just now. Try again in a moment."

    /// Whether the person has sent nothing yet, for the empty list.
    static func hasNoFeedback(_ screen: String?) -> Bool { screen == "feedback-list-empty" }

    /// Whether the list of feedback cannot be read, for the error state.
    static let listFailureMessage = "Your feedback could not be read just now. Try again in a moment."

    static func failsToList(_ screen: String?) -> Bool { screen == "feedback-list-error" }

    static func tickets(stamp: (TimeInterval) -> String) -> [[String: Any]] {
        func row(_ id: String, _ sequence: Int, _ words: String, _ status: String, requester: String, secondsAgo: TimeInterval) -> [String: Any] {
            [
                "id": id, "sequence": sequence, "title": "Portal feedback: " + words, "status": status, "priority": "normal", "organizationId": "organization01",
                "authorUserId": requester, "requesterUserId": requester, "assigneeUserId": status == "new" ? NSNull() : "user02",
                "assigneeUserIds": status == "new" ? [] : ["user02"], "isInternal": false, "createdAt": stamp(secondsAgo + 7_200), "modifiedAt": stamp(secondsAgo),
                "description": words, "viewerCapabilities": [], "isPortalFeedback": true,
            ]
        }
        return [
            row(ticketId, 21, "The filter menu on Tickets is hard to find", "open", requester: "user01", secondsAgo: 86_400),
            row("feedback02", 17, "Camera tiles are too dim in dark mode", "solved", requester: "user01", secondsAgo: 300_000),
            row("feedback03", 12, "The site list could remember my last search", "new", requester: "user01", secondsAgo: 1_200_000),
            row("feedback04", 14, "Another person's idea for the chat screen", "open", requester: "user03", secondsAgo: 500_000),
        ]
    }

    static func comments(stamp: (TimeInterval) -> String) -> [String: [[String: Any]]] {
        [
            ticketId: [
                [
                    "id": "feedbackcomment01", "authorUserId": "user01", "isOriginalRequest": true, "isInternal": false, "createdAt": stamp(93_600),
                    "body": "The filter menu on Tickets is hard to find. I looked for it in the list itself before I saw the small icon at the top.",
                ]
            ]
        ]
    }
}
