import Foundation

/// PortalError is why something the app asked of a server did not happen.
public enum PortalError: Error, Equatable, Sendable, LocalizedError {
    /// The server ended this sign-in: it refused the refresh token, or refused
    /// a request again with a freshly renewed token.
    case signedOut
    /// The server refused one request even with a fresh token. The sign-in is intact: only the sign-in's own refusal (`invalid_grant`) ends it.
    case notPermitted
    /// The server said no, in its own words.
    case refused(String)
    /// The server answered with something the app cannot read.
    case unreadableAnswer
    /// The address typed is not a server address the app will talk to.
    case invalidServerAddress
    /// The server cannot sign this app in yet.
    case clientNotRegistered(String)
    /// A question or approval card that is no longer open: someone answered
    /// it, it was cancelled or it timed out. `reason` is `answered`, `cancelled` or `expired`.
    case cardNoLongerWaiting(reason: String)
    /// A chat message was posted but the assistant already answers three other members.
    case assistantBusy(String)

    public var errorDescription: String? {
        switch self {
        case .signedOut: "This sign-in has ended. Sign in again."
        case .notPermitted: "The server did not allow that."
        case .refused(let message): message
        case .unreadableAnswer: "The server sent an answer the app cannot read."
        case .invalidServerAddress: "Enter a server address that starts with https://."
        case .clientNotRegistered(let message): message
        case .cardNoLongerWaiting(let reason):
            switch reason {
            case "answered": "That was already answered."
            case "expired": "That question timed out."
            default: "That was cancelled."
            }
        case .assistantBusy: "Your message was posted. The assistant is answering other people and will not reply to it."
        }
    }

    /// The error a GraphQL error stands for: a known code becomes its own
    /// case, anything else keeps the server's words.
    init(graphQLError error: Connection.GraphQLError) {
        switch error.extensions?.code {
        case "CARD_NO_LONGER_WAITING": self = .cardNoLongerWaiting(reason: error.extensions?.reason ?? "")
        case "ASSISTANT_BUSY": self = .assistantBusy(error.message)
        default: self = .refused(error.message)
        }
    }
}
