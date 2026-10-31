import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// HTTPTransport sends one request and returns the answer: URLSession in the
/// app, a fake in tests and in the demo.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSessionTransport is the real network.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response = response as? HTTPURLResponse {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: PortalError.unreadableAnswer)
                }
            }
            task.resume()
        }
    }
}
