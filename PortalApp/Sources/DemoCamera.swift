import Foundation
import PortalKit
import UIKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// DemoCameraClip is the one test-pattern clip every demo camera plays: six
/// one-second fragments of an encoder's test pattern (`DemoCamera.mp4`, made
/// with a software encoder, nothing recorded by a camera). It is cut into the
/// pieces the NVR's stream is made of, and each fragment's time stamp is
/// rewritten to the wall clock, so the app sees what a camera sends.
final class DemoCameraClip: @unchecked Sendable {
    static let shared = DemoCameraClip()

    let initSegment: Data
    let codec: String
    let fragments: [Data]
    let timescale: UInt64
    let fragmentTicks: UInt64

    private init() {
        let file = Bundle.main.url(forResource: "DemoCamera", withExtension: "mp4").flatMap { try? Data(contentsOf: $0) } ?? Data()
        var initData = Data()
        var parts: [Data] = []
        var offset = 0
        var pendingMovieFragment: Data?
        while offset + 8 <= file.count {
            let size = Self.bigEndian(file, offset)
            guard size >= 8, offset + size <= file.count else { break }
            let type = String(decoding: file[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let box = file[offset..<(offset + size)]
            switch type {
            case "ftyp", "moov": initData.append(box)
            case "moof": pendingMovieFragment = Data(box)
            case "mdat":
                if var movieFragment = pendingMovieFragment {
                    movieFragment.append(box)
                    parts.append(movieFragment)
                    pendingMovieFragment = nil
                }
            default: break
            }
            offset += size
        }
        initSegment = initData
        fragments = parts
        let video = (try? CameraMP4.parseInitSegment(initData))?.video
        timescale = UInt64(video?.timescale ?? 10_240)
        fragmentTicks = UInt64(parts.first.flatMap { CameraMP4.parseFragment($0).first?.durationTicks } ?? 10_240)
        if let sequenceSet = video?.parameterSets.first, sequenceSet.count >= 4 {
            codec = String(format: "avc1.%02x%02x%02x", sequenceSet[sequenceSet.startIndex + 1], sequenceSet[sequenceSet.startIndex + 2], sequenceSet[sequenceSet.startIndex + 3])
        } else {
            codec = "avc1.4d401e"
        }
    }

    private static func bigEndian(_ data: Data, _ offset: Int) -> Int {
        var value = 0
        for index in 0..<4 { value = (value << 8) + Int(data[data.startIndex + offset + index]) }
        return value
    }

    var fragmentSeconds: Double { Double(fragmentTicks) / Double(timescale) }

    /// The codec and initialization frames, as one message.
    var openingMessage: Data {
        CameraFrame(typeByte: CameraFrameType.codecInfo.rawValue, payload: Data(codec.utf8)).encoded
            + CameraFrame(typeByte: CameraFrameType.initSegment.rawValue, payload: initSegment).encoded
    }

    /// Fragment number `index` of a stream that starts at `startEpochMS`, as the frames the NVR sends, cut into two websocket messages so the
    /// app has to join a frame split across them.
    func messages(forFragment index: Int, startEpochMS: Double) -> [Data] {
        guard !fragments.isEmpty else { return [] }
        let base = UInt64(max(startEpochMS, 0) / 1000 * Double(timescale)) + UInt64(index) * fragmentTicks
        guard let fragment = CameraMP4.settingDecodeTime(fragments[index % fragments.count], to: base), fragment.count > 8 else { return [] }
        let moofSize = Self.bigEndian(fragment, 0)
        guard moofSize > 8, moofSize < fragment.count else { return [] }
        let moof = fragment.prefix(moofSize)
        let mdat = fragment.dropFirst(moofSize)
        let encoded =
            CameraFrame(typeByte: CameraFrameType.beginSegment.rawValue, payload: Data()).encoded
            + CameraFrame(typeByte: CameraFrameType.moof.rawValue, payload: Data(moof)).encoded
            + CameraFrame(typeByte: CameraFrameType.mdat.rawValue, payload: Data(mdat)).encoded
            + CameraFrame(typeByte: CameraFrameType.endSegment.rawValue, payload: Data()).encoded
        let cut = min(1_000, encoded.count / 2)
        return [Data(encoded.prefix(cut)), Data(encoded.dropFirst(cut))]
    }
}

/// DemoCameraSocket plays the test-pattern clip as a camera stream: live, one
/// fragment a second as it would arrive; or a recorded window, dumped at once
/// and then left open and silent, as the NVR does.
final class DemoCameraSocket: CameraSocket, @unchecked Sendable {
    private struct State {
        var queue: [Data] = []
        var nextFragment = 0
        var isClosed = false
        var end: CameraSocketEnd?
    }

    private let clip = DemoCameraClip.shared
    private let state = DemoLocked(State())
    private let isLive: Bool
    private let startEpochMS: Double
    private let windowFragmentCount: Int
    private let openedAt = Date()

    init(url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> Double? { items.first { $0.name == name }?.value.flatMap(Double.init) }
        let live = url.path.contains("/livestream/")
        let now = Date().timeIntervalSince1970 * 1000
        isLive = live
        startEpochMS = live ? now : (value("start") ?? now)
        let windowMS = max((value("end") ?? now) - (value("start") ?? now), 0)
        windowFragmentCount = Int((windowMS / 1000 / DemoCameraClip.shared.fragmentSeconds).rounded(.up))
        state.withValue { $0.queue = [DemoCameraClip.shared.openingMessage] }
        // The unsupported-controller screenshot has a controller whose software has no playback route: the upgrade is not accepted.
        if !live, ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "camera-unsupported" {
            state.withValue {
                $0.queue = []
                $0.isClosed = true
                $0.end = .refused(statusCode: 200)
            }
        }
        // The unreachable screenshot has a controller that Portal cannot get an answer from.
        if !live, ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "camera-unreachable" {
            state.withValue {
                $0.queue = []
                $0.isClosed = true
                $0.end = .refused(statusCode: 503)
            }
        }
        // The failed-picture screenshot has one camera whose live stream Portal refuses, as it refuses its snapshot, and one whose controller
        // does not answer, which is retried.
        if live, ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "cameras-failed" {
            let refusal = url.path.hasSuffix("/nvrcamera03") ? 403 : (url.path.hasSuffix("/nvrcamera02") ? 503 : nil)
            if let refusal {
                state.withValue {
                    $0.queue = []
                    $0.isClosed = true
                    $0.end = .refused(statusCode: refusal)
                }
            }
        }
        // Like a real NVR, which records the sharpest and the least sharp channel only: asked for the middle one it closes the socket.
        if !live, value("channel") == 1 {
            state.withValue {
                $0.queue = []
                $0.isClosed = true
                $0.end = .closed(code: 1011, reason: "no recorded footage for the requested window")
            }
        }
    }

    var end: CameraSocketEnd? { state.withValue { $0.end } }

    func receive() async throws -> Data? {
        while true {
            let step: (message: Data?, isClosed: Bool, waitSeconds: Double) = state.withValue { current in
                if current.isClosed { return (nil, true, 0) }
                if !current.queue.isEmpty { return (current.queue.removeFirst(), false, 0) }
                let index = current.nextFragment
                if isLive {
                    let due = openedAt.addingTimeInterval(Double(index) * clip.fragmentSeconds)
                    let wait = due.timeIntervalSinceNow
                    if wait > 0 { return (nil, false, min(wait, 0.1)) }
                } else if index >= windowFragmentCount {
                    // The window is delivered. The NVR leaves the socket open and says nothing more.
                    return (nil, false, 0.1)
                }
                current.queue = clip.messages(forFragment: index, startEpochMS: startEpochMS)
                current.nextFragment += 1
                return (current.queue.isEmpty ? nil : current.queue.removeFirst(), false, 0)
            }
            if step.isClosed { return nil }
            if let message = step.message { return message }
            try await Task.sleep(nanoseconds: UInt64(max(step.waitSeconds, 0.01) * 1_000_000_000))
        }
    }

    func close() {
        state.withValue { $0.isClosed = true }
    }
}

/// DemoCameraPaths answers the plain requests of the camera routes: the bootstrap document, a snapshot and, only after a playback dial failed, what the playback route answers.
enum DemoCameraPaths {
    static func respond(to request: URLRequest) -> (Data, HTTPURLResponse) {
        let url = request.url!
        func reply(_ status: Int, _ body: Data, contentType: String) -> (Data, HTTPURLResponse) {
            (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!)
        }
        let parts = url.path.split(separator: "/").map(String.init)
        // ["api", "v1", "unifiprotect", controllerId, kind, cameraId]
        let kind = parts.count > 4 ? parts[4] : ""
        switch kind {
        case "bootstrap":
            let body = try? JSONSerialization.data(withJSONObject: ["nvr": ["timezone": DemoCameras.timeZone], "cameras": [Any]()])
            return reply(200, body ?? Data(), contentType: "application/json")
        case "snapshot":
            let cameraId = parts.count > 5 ? parts[5] : ""
            // The failed-picture screenshot has one camera Portal refuses and one the NVR cannot answer for.
            if ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "cameras-failed" {
                if cameraId == "nvrcamera03" { return reply(403, Data(), contentType: "text/plain") }
                if cameraId == "nvrcamera02" { return reply(502, Data(), contentType: "text/plain") }
            }
            let index = DemoCameras.everything.firstIndex { ($0["originCameraId"] as? String) == cameraId } ?? 0
            return reply(200, DemoPictures.cameraFrame(variant: index), contentType: "image/jpeg")
        case "playback":
            // A websocket route answers a plain GET with 400. The screenshot of a controller too old to have it gets its web page.
            if ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "camera-unsupported" {
                return reply(200, Data("<html></html>".utf8), contentType: "text/html")
            }
            if ProcessInfo.processInfo.environment["PORTAL_DEMO_SCREEN"] == "camera-unreachable" {
                return reply(502, Data(), contentType: "text/plain")
            }
            return reply(400, Data(), contentType: "text/plain")
        default:
            return reply(404, Data(), contentType: "text/plain")
        }
    }
}

/// DemoCameras are the invented cameras of the demo site.
enum DemoCameras {
    static let timeZone = "America/Chicago"

    private static func channels() -> [[String: Any]] {
        [
            ["id": 0, "name": "High", "isEnabled": true, "width": 2688, "height": 1512, "fps": 24],
            ["id": 1, "name": "Medium", "isEnabled": true, "width": 1280, "height": 720, "fps": 24],
            ["id": 2, "name": "Low", "isEnabled": true, "width": 640, "height": 360, "fps": 24],
        ]
    }

    private static func camera(_ id: String, _ origin: String, _ name: String, isOnline: Bool, site: String = "site01", organization: String = "organization01") -> [String: Any] {
        [
            "id": id, "organizationId": organization, "siteId": site, "controllerId": "controller01", "originCameraId": origin, "name": name, "kind": "dome",
            "status": isOnline ? "online" : "offline", "timeZone": timeZone, "isControllerConnected": true, "channels": channels(),
        ]
    }

    /// The cameras of the demo's first site.
    static var all: [[String: Any]] {
        [
            camera("camera01", "nvrcamera01", "Dock door 1", isOnline: true),
            camera("camera02", "nvrcamera02", "Pick station 3", isOnline: true),
            camera("camera03", "nvrcamera03", "Aisle 4 overhead", isOnline: true),
            camera("camera04", "nvrcamera04", "Charging area", isOnline: false),
        ]
    }

    /// The cameras of the demo's other sites, which the surveillance wall shows beside the first site's.
    static var others: [[String: Any]] {
        [
            camera("camera05", "nvrcamera05", "Loading bay", isOnline: true, site: "site02"),
            camera("camera06", "nvrcamera06", "Oven hall", isOnline: true, site: "site03", organization: "organization02"),
            camera("camera07", "nvrcamera07", "Packing table", isOnline: true, site: "site03", organization: "organization02"),
            camera("camera08", "nvrcamera08", "Freezer aisle", isOnline: false, site: "site04", organization: "organization02"),
        ]
    }

    /// More cameras than the wall streams at once, for the screenshots of a long wall.
    static var many: [[String: Any]] {
        (1...20).map { number in
            camera(String(format: "camera%02d", 20 + number), String(format: "nvrcamera%02d", 20 + number), "Dock bay \(number)", isOnline: true)
        }
    }

    /// Whether this run shows a wall of more cameras than the limit of streams.
    static var isLongWall: Bool { DemoOptions.screen == "surveillance-many" || DemoOptions.screen == "surveillance-many-scrolled" }

    /// Every camera of the demo, in the order the pictures are varied.
    static var everything: [[String: Any]] { all + others + (isLongWall ? many : []) }

    static func respond(operation: String, variables: [String: Any]) -> [String: Any]? {
        switch operation {
        case "ListCameras":
            // A customer sees the cameras of its own organization; a Mujin user sees every camera, or one site's when asked.
            let visible = everything.filter { DemoOptions.isStaff || ($0["organizationId"] as? String) == "organization01" }
            let siteId = variables["siteId"] as? String
            let cell = DemoCells.cell(variables)
            return ["ListCameras": ["cameras": visible.filter { (siteId == nil || ($0["siteId"] as? String) == siteId) && (cell == nil || cell!.cameraIds.contains($0["id"] as? String ?? "")) }]]
        case "GetCamera":
            let identifier = variables["cameraId"] as? String ?? ""
            if let found = everything.first(where: { ($0["id"] as? String) == identifier }) { return ["GetCamera": ["camera": found]] }
            return ["GetCamera": ["camera": NSNull()]]
        case "ListIncidentCameras":
            let detected = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2_400 - 10))
            return [
                "ListIncidentCameras": [
                    "incidentCameras": [
                        ["id": "incidentcamera01", "incidentId": "incident01", "cameraId": "camera02", "cameraName": "Pick station 3", "isPrimary": true, "clipStartedAt": detected],
                        ["id": "incidentcamera02", "incidentId": "incident01", "cameraId": "camera03", "cameraName": "Aisle 4 overhead", "isPrimary": false, "clipStartedAt": detected],
                    ]
                ]
            ]
        default:
            return nil
        }
    }
}
