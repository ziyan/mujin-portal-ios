import AuthenticationServices
import PortalKit
import UIKit

/// WebSignIn shows a server's sign-in page in the system's web authentication
/// sheet and waits for it to return to the app's redirect address.
@MainActor
final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Cancelled: Error { case cancelled }

    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(PortalClient.callbackScheme)) { returned, error in
                if let returned {
                    continuation.resume(returning: returned)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: Cancelled.cancelled)
                } else {
                    continuation.resume(throwing: error ?? PortalError.unreadableAnswer)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: PortalError.refused(String(localized: "The sign-in page could not be opened.")))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first.map { ASPresentationAnchor(windowScene: $0) } ?? ASPresentationAnchor()
        }
    }
}
