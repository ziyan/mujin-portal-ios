import Foundation

/// CameraFailure is why a camera's picture, stream or clip did not come, in the two kinds a person can tell apart: Portal would not
/// allow it, or it could not be had.
public enum CameraFailure: Equatable, Sendable {
    /// Portal refused the request (401 or 403), even with a fresh token.
    case notAllowed
    /// Anything else: the NVR or its controller did not answer, the network failed, or the server had an error.
    case unavailable

    /// The HTTP status a failed fetch names, such as 401 for `refused("HTTP 401")`.
    public static func status(of error: Error) -> Int? {
        guard case PortalError.refused(let message)? = error as? PortalError, message.hasPrefix("HTTP ") else { return nil }
        return Int(message.dropFirst("HTTP ".count))
    }

    public static func classify(_ error: Error) -> CameraFailure {
        if let portalError = error as? PortalError, portalError == .notPermitted { return .notAllowed }
        if let status = status(of: error), status == 401 || status == 403 { return .notAllowed }
        return .unavailable
    }
}

extension Connection {
    /// Why a camera's picture cannot be had right now, found with one snapshot request; nil when the picture comes.
    public func snapshotFailure(controllerId: String, cameraId: String) async -> CameraFailure? {
        do {
            _ = try await fetch(path: CameraRoutes.snapshotPath(controllerId: controllerId, cameraId: cameraId, cacheBust: Int(Date().timeIntervalSince1970)))
            return nil
        } catch {
            return CameraFailure.classify(error)
        }
    }
}
