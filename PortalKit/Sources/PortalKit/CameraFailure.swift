import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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

/// CameraPlaybackFailure is why the playback websocket of a recorded stream could not be opened, in the three kinds a person can tell
/// apart.
public enum CameraPlaybackFailure: Equatable, Sendable {
    /// Portal refused the request (401 or 403).
    case notAllowed
    /// The controller is online but its software has no playback route: the upgrade is answered with its web page, or Portal has no
    /// such route at all.
    case unsupported
    /// The controller or the network did not answer (502 to 504, or nothing), or the route exists and the dial failed anyway.
    case unreachable

    /// What one plain GET to the playback route says about a dial that failed. A route that exists answers a plain GET with 400 (the
    /// upgrade header is missing); an older controller answers any unknown address with its page (200), and a Portal without the proxy
    /// route says 404.
    public static func classify(statusCode: Int?) -> CameraPlaybackFailure {
        guard let statusCode else { return .unreachable }
        if statusCode == 401 || statusCode == 403 { return .notAllowed }
        if statusCode == 200 || statusCode == 404 { return .unsupported }
        return .unreachable
    }
}

extension Connection {
    /// Finds out why a playback socket did not open, with one plain GET. Asked only after a dial failed, never ahead of one.
    public func playbackFailure(controllerId: String, cameraId: String) async -> CameraPlaybackFailure {
        var request = URLRequest(url: server.endpoint(CameraRoutes.playbackPath(controllerId: controllerId, cameraId: cameraId, channel: 0, startMS: 1, endMS: 2)))
        request.timeoutInterval = 15
        let status: Int?
        do {
            status = try await send(authorizing: request).1.statusCode
        } catch PortalError.notPermitted {
            // A request refused even with a fresh token is a refusal of this camera.
            status = 401
        } catch {
            status = nil
        }
        return CameraPlaybackFailure.classify(statusCode: status)
    }
}
