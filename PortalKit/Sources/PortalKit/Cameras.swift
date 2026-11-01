import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// CameraChannel is one stream a camera offers. Channel 0 is the sharpest.
public struct CameraChannel: Codable, Equatable, Hashable, Sendable {
    public let id: Int?
    public let name: String?
    public let isEnabled: Bool?
    public let width: Int?
    public let height: Int?
    public let fps: Int?

    public init(id: Int?, name: String? = nil, isEnabled: Bool? = true, width: Int? = nil, height: Int? = nil, fps: Int? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.width = width
        self.height = height
        self.fps = fps
    }

    var pixelCount: Int { (width ?? 0) * (height ?? 0) }
}

/// Camera is a camera in Portal's registry, with the controller whose NVR serves its pictures.
public struct Camera: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// The registry's id, which names the camera in Portal.
    public let id: String
    public let organizationId: String?
    public let siteId: String?
    public let controllerId: String
    /// The NVR's own id for the camera, which every picture and stream route takes.
    public let originCameraId: String
    public let name: String?
    public let kind: String?
    /// `online` or `offline`, as the last sweep of the NVR found it.
    public let status: String?
    /// The NVR's zone, such as `America/Chicago`.
    public let timeZone: String?
    public let isControllerConnected: Bool?
    public let channels: [CameraChannel]?

    public init(
        id: String, organizationId: String? = nil, siteId: String? = nil, controllerId: String, originCameraId: String, name: String? = nil,
        kind: String? = nil, status: String? = nil, timeZone: String? = nil, isControllerConnected: Bool? = nil, channels: [CameraChannel]? = nil
    ) {
        self.id = id
        self.organizationId = organizationId
        self.siteId = siteId
        self.controllerId = controllerId
        self.originCameraId = originCameraId
        self.name = name
        self.kind = kind
        self.status = status
        self.timeZone = timeZone
        self.isControllerConnected = isControllerConnected
        self.channels = channels
    }

    public var displayName: String {
        let text = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? originCameraId : text
    }

    /// Both halves have to hold: the NVR last reported the camera online, and the controller that serves it is connected now.
    public var isStreamable: Bool { status?.lowercased() == "online" && isControllerConnected == true }
}

/// CameraQuality is the stream-quality choice, resolved against each camera's enabled channels.
public enum CameraQuality: String, CaseIterable, Equatable, Sendable {
    case low
    case medium
    case high

    /// The enabled channels, sharpest first.
    static func enabledChannels(_ channels: [CameraChannel]?) -> [CameraChannel] {
        (channels ?? []).filter { $0.isEnabled == true && $0.id != nil }.sorted { $0.pixelCount > $1.pixelCount }
    }

    /// The channel for this quality: the sharpest is high, the least sharp is low, anything between is medium. A camera
    /// that lists no channels is streamed on channel 0.
    public func channelId(of channels: [CameraChannel]?) -> Int {
        let enabled = Self.enabledChannels(channels)
        guard let sharpest = enabled.first, let least = enabled.last else { return 0 }
        switch self {
        case .high: return sharpest.id ?? 0
        case .low: return least.id ?? 0
        case .medium: return enabled[enabled.count / 2].id ?? 0
        }
    }

    /// The qualities a camera offers: one per distinct channel, so a camera with a single stream offers none to choose.
    public static func offered(by channels: [CameraChannel]?) -> [CameraQuality] {
        let count = enabledChannels(channels).count
        if count <= 1 { return [] }
        if count == 2 { return [.low, .high] }
        return [.low, .medium, .high]
    }
}

/// IncidentCameraTarget is an angle of an incident: the camera and where to
/// start looking.
public struct IncidentCameraTarget: Equatable, Hashable, Sendable {
    public let camera: Camera
    /// When the stored clip began, if the incident has one.
    public let clipStartedAt: Date?
}

extension Documents {
    static let cameraFields = """
        id organizationId siteId controllerId originCameraId name kind status timeZone isControllerConnected
        channels { id name isEnabled width height fps }
        """

    public static let listCameras = """
        query ListCameras($siteId: String, $controllerId: String) {
          ListCameras(siteId: $siteId, controllerId: $controllerId) { cameras { \(cameraFields) } }
        }
        """

    public static let getCamera = """
        query GetCamera($cameraId: String) {
          GetCamera(cameraId: $cameraId) { camera { \(cameraFields) } }
        }
        """

    public static let listIncidentCameras = """
        query ListIncidentCameras($incidentId: String) {
          ListIncidentCameras(incidentId: $incidentId) {
            incidentCameras { id incidentId cameraId cameraName controllerId originCameraId clipStartedAt timeZone isPrimary }
          }
        }
        """

    static var cameraDocuments: [String] { [listCameras, getCamera, listIncidentCameras] }
}

extension Connection {
    /// The cameras of a site, the ones that can be streamed first and then by name.
    public func cameras(siteId: String) async throws -> [Camera] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let cameras: [Lossy<Camera>?]? }
            let ListCameras: List?
        }
        let rows = try await execute(Documents.listCameras, variables: ["siteId": .string(siteId)], as: Answer.self).ListCameras?.cameras ?? []
        return CameraOrdering.ordered(rows.compactMap { $0?.value })
    }

    public func camera(id: String) async throws -> Camera? {
        struct Answer: Decodable, Sendable {
            struct One: Decodable, Sendable { let camera: Camera? }
            let GetCamera: One?
        }
        return try await execute(Documents.getCamera, variables: ["cameraId": .string(id)], as: Answer.self).GetCamera?.camera
    }

    /// The angles an incident has, each with its camera read in full so the channels are known. The primary angle comes first.
    public func incidentCameraTargets(incidentId: String) async throws -> [IncidentCameraTarget] {
        struct Row: Decodable, Sendable {
            let cameraId: String?
            let clipStartedAt: String?
            let isPrimary: Bool?
        }
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let incidentCameras: [Row?]? }
            let ListIncidentCameras: List?
        }
        let rows = try await execute(Documents.listIncidentCameras, variables: ["incidentId": .string(incidentId)], as: Answer.self)
            .ListIncidentCameras?.incidentCameras?.compactMap { $0 } ?? []
        var targets: [IncidentCameraTarget] = []
        // An angle whose camera is gone from the registry has nothing to open.
        for row in rows.sorted(by: { ($0.isPrimary ?? false) && !($1.isPrimary ?? false) }) {
            guard let cameraId = row.cameraId, !cameraId.isEmpty, let resolved = try await camera(id: cameraId) else { continue }
            targets.append(IncidentCameraTarget(camera: resolved, clipStartedAt: PortalDate.parse(row.clipStartedAt)))
        }
        return targets
    }

    /// The NVR's time zone from its bootstrap document, for a camera whose registry row has none.
    public func nvrTimeZone(controllerId: String) async -> String? {
        struct Bootstrap: Decodable, Sendable {
            struct NVR: Decodable, Sendable { let timezone: String? }
            let nvr: NVR?
        }
        var request = URLRequest(url: server.endpoint(CameraRoutes.bootstrapPath(controllerId: controllerId)))
        request.timeoutInterval = 20
        guard let (data, response) = try? await send(authorizing: request), response.statusCode == 200,
            let identifier = (try? JSONDecoder().decode(Bootstrap.self, from: data))?.nvr?.timezone, TimeZone(identifier: identifier) != nil
        else { return nil }
        return identifier
    }
}

/// Lossy reads a row as nil instead of failing the whole list when one row is missing a field the app needs.
struct Lossy<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// CameraOrdering lists the cameras that can be watched first, then by name.
public enum CameraOrdering {
    public static func ordered(_ cameras: [Camera]) -> [Camera] {
        cameras.sorted { left, right in
            if left.isStreamable != right.isStreamable { return left.isStreamable }
            return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
        }
    }
}
