import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// PKCE is the proof that the app that started a sign-in is the one that
/// finishes it (RFC 7636, method S256).
public struct PKCE: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    /// Makes a new verifier from 32 random bytes.
    public init() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        self.init(verifier: Self.base64URL(Data(bytes)))
    }

    /// The challenge for a given verifier.
    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// A random value for the OAuth state parameter.
    public static func randomState() -> String {
        PKCE().verifier
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
