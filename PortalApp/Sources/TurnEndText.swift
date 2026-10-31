import Foundation
import PortalKit

/// TurnEndText words a turn's end in the person's language. The server sends
/// a reason kind with its parameters and an English sentence; a kind the app
/// does not know keeps the server's sentence.
enum TurnEndText {
    static func sentence(for reason: TurnEndReason) -> String? {
        let parameters = reason.parameters
        switch reason.kind {
        case "contextTooLong": return String(localized: "This conversation is too long for the assistant to go on. Start a new one.")
        case "providerCredentials": return String(localized: "The assistant's model provider rejected its credentials. An administrator needs to fix this.")
        case "providerRateLimited": return String(localized: "The model provider is busy. Try again in a minute.")
        case "providerUnavailable": return String(localized: "The model provider is not available right now. Try again soon.")
        case "providerRefused":
            let status = parameters["httpStatus"] ?? ""
            return status.isEmpty
                ? String(localized: "The model provider refused the request.") : String(localized: "The model provider refused the request (HTTP \(status)).")
        case "connectionInterrupted": return String(localized: "The connection was interrupted before the answer finished.")
        case "roundLimit":
            let count = parameters["roundCount"] ?? ""
            return count.isEmpty
                ? String(localized: "The assistant stopped before it finished. Ask it to go on.")
                : String(localized: "The assistant stopped after \(count) steps without finishing. Ask it to go on.")
        case "repeatedFailure":
            let tool = (parameters["toolName"] ?? "").replacingOccurrences(of: "_", with: " ")
            return tool.isEmpty
                ? String(localized: "The assistant stopped because a tool kept failing.")
                : String(localized: "The assistant stopped because \(tool) kept failing.")
        case "stoppedByUser": return String(localized: "Stopped")
        case "queuedBehindRun": return String(localized: "Waiting for the assistant to finish another answer first.")
        case "unreadableToolCall":
            let tool = (parameters["toolName"] ?? "").replacingOccurrences(of: "_", with: " ")
            return tool.isEmpty
                ? String(localized: "The assistant's tool call could not be read, so it tried again.")
                : String(localized: "The assistant's call to \(tool) could not be read, so it tried again.")
        default: return nil
        }
    }

    /// The words for the reason a speak-first conversation began.
    static func speakFirstReason(_ reason: String) -> String {
        switch reason {
        case "onboarding": String(localized: "to get to know you")
        case "goal_needs_you": String(localized: "a goal needs you")
        case "memory_check": String(localized: "to check what it remembers")
        case "idea": String(localized: "it has an idea")
        default: reason.replacingOccurrences(of: "_", with: " ")
        }
    }
}
