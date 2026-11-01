import Foundation
import PortalKit

extension Error {
    /// What to tell the person: the app's own words for its own errors, and the
    /// server's or the system's words for theirs.
    var userMessage: String {
        guard let error = self as? PortalError else { return localizedDescription }
        switch error {
        case .signedOut: return String(localized: "This sign-in has ended. Sign in again.")
        case .notPermitted: return String(localized: "The server did not allow that.")
        case .invalidServerAddress: return String(localized: "Enter a server address that starts with https://.")
        case .unreadableAnswer: return String(localized: "The server sent an answer the app cannot read.")
        case .refused(let message), .clientNotRegistered(let message): return message
        case .cardNoLongerWaiting(let reason):
            switch reason {
            case "answered": return String(localized: "That was already answered.")
            case "expired": return String(localized: "That question timed out.")
            default: return String(localized: "That was cancelled.")
            }
        case .assistantBusy: return String(localized: "Your message was posted. The assistant is answering other people and will not reply to it.")
        }
    }
}
