import Foundation

/// PortalError is why something the app asked of a server did not happen.
public enum PortalError: Error, Equatable, Sendable, LocalizedError {
    /// The server ended this sign-in: it refused the refresh token, or refused
    /// a request again with a freshly renewed token.
    case signedOut
    /// The server said no, in its own words.
    case refused(String)
    /// The server answered with something the app cannot read.
    case unreadableAnswer
    /// The address typed is not a server address the app will talk to.
    case invalidServerAddress
    /// The server cannot sign this app in yet.
    case clientNotRegistered(String)

    public var errorDescription: String? {
        switch self {
        case .signedOut: "This sign-in has ended. Sign in again."
        case .refused(let message): message
        case .unreadableAnswer: "The server sent an answer the app cannot read."
        case .invalidServerAddress: "Enter a server address that starts with https://."
        case .clientNotRegistered(let message): message
        }
    }
}
