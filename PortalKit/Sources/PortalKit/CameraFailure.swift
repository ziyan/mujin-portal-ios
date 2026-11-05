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

/// CameraPlaybackFailure is why the playback websocket of a recorded stream could not be opened, in the kinds a person can tell apart.
public enum CameraPlaybackFailure: Equatable, Sendable {
    /// Portal refused the request (401 or 403).
    case notAllowed
    /// The controller is online but its software has no playback route: the upgrade is answered with its web page, or Portal has no
    /// such route at all.
    case unsupported
    /// The controller or the network did not answer (502 to 504, or nothing).
    case unreachable
    /// The controller answered and has no recording in the window it was asked for. That is a gap in the footage, not a fault.
    case noRecording
    /// The route exists and the socket still failed, and nothing says why.
    case undetermined

    /// The text the NVR's playback route gives when it has nothing in a window.
    static let noRecordingReason = "no recorded footage"

    /// What the end of the socket itself says, or nil when it says too little and a plain GET should be asked.
    public static func classify(socketEnd: CameraSocketEnd?) -> CameraPlaybackFailure? {
        switch socketEnd {
        case .refused(let statusCode)?:
            let failure = classify(statusCode: statusCode)
            // A 400 is what a route that exists says to a request that is not an upgrade; it tells nothing about why the dial failed.
            return statusCode == 400 ? nil : failure
        case .closed(let code, let reason)?:
            if code == 1011, reason.lowercased().contains(noRecordingReason) { return .noRecording }
            return nil
        case .broken?, nil:
            return nil
        }
    }

    /// What one plain GET to the playback route says about a dial that failed. A route that exists answers a plain GET with 400 (the
    /// upgrade header is missing); an older controller answers any unknown address with its page (200), and a Portal without the proxy
    /// route says 404.
    public static func classify(statusCode: Int?) -> CameraPlaybackFailure {
        guard let statusCode else { return .unreachable }
        if statusCode == 401 || statusCode == 403 { return .notAllowed }
        if statusCode == 200 || statusCode == 404 { return .unsupported }
        if statusCode == 502 || statusCode == 503 || statusCode == 504 { return .unreachable }
        return .undetermined
    }
}

/// CameraLiveFailure is what the end of a live stream's socket says about trying again. A refusal or a missing route is the same on the
/// next try, so it is final; a drop, a timeout or a controller that did not answer may pass, so it is retried with backoff.
public enum CameraLiveFailure: Equatable, Sendable {
    /// Portal refused the upgrade (401 or 403). The person's access does not change by asking again.
    case notAllowed
    /// Portal has no live route for the camera (404).
    case routeMissing
    /// Anything else: the socket dropped, timed out, was closed by the server or was refused for a reason that may pass (5xx).
    case transient

    public static func classify(socketEnd: CameraSocketEnd?) -> CameraLiveFailure {
        guard case .refused(let statusCode)? = socketEnd else { return .transient }
        switch statusCode {
        case 401, 403: return .notAllowed
        case 404: return .routeMissing
        default: return .transient
        }
    }

    /// Whether asking again is pointless: only the person can try again, from the camera's own screen.
    public var isFinal: Bool { self != .transient }
}

extension Connection {
    /// Finds out why a playback socket did not open, with one plain GET. Asked only after a dial failed, and only when the socket's own
    /// end did not say. It can tell a refusal, a route the controller does not have and a controller that does not answer; a route that
    /// exists answers 400, which leaves the cause undetermined.
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
