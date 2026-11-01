import Foundation

/// CameraFrameType is the first byte of a frame in the stream a camera's
/// websocket carries. The numbers are the NVR's: Portal relays the same
/// framing for live video and for recorded windows.
public enum CameraFrameType: UInt8, Sendable {
    /// The codec string, such as `avc1.640028` or `hvc1.1.6.L93.B0`.
    case codecInfo = 248
    case beginSegment = 249
    /// The fragmented MP4 initialization segment (`ftyp` and `moov`).
    case initSegment = 250
    case moof = 251
    case video = 252
    case audio = 253
    case mdat = 254
    case endSegment = 255
}

/// CameraFrame is one frame of the stream: a type byte, a three byte
/// big-endian length, and the payload.
public struct CameraFrame: Equatable, Sendable {
    public let typeByte: UInt8
    public let payload: Data

    public init(typeByte: UInt8, payload: Data) {
        self.typeByte = typeByte
        self.payload = payload
    }

    public var type: CameraFrameType? { CameraFrameType(rawValue: typeByte) }

    /// The bytes of the frame as they travel, for tests and for the demo server.
    public var encoded: Data {
        var bytes = Data([typeByte, UInt8((payload.count >> 16) & 0xff), UInt8((payload.count >> 8) & 0xff), UInt8(payload.count & 0xff)])
        bytes.append(payload)
        return bytes
    }
}

/// CameraFrameDecoder cuts the byte stream into frames. A websocket message
/// may end in the middle of a frame, so the rest waits for the next one.
public struct CameraFrameDecoder: Sendable {
    /// The largest payload a three byte length can describe.
    public static let maximumPayloadCount = (1 << 24) - 1

    private var pending: [UInt8] = []
    private var readOffset = 0

    public init() {}

    /// The bytes held back until the rest of their frame arrives.
    public var pendingByteCount: Int { pending.count - readOffset }

    /// Adds the bytes of one message and returns every frame it completed.
    public mutating func append(_ data: Data) -> [CameraFrame] {
        pending.append(contentsOf: data)
        var frames: [CameraFrame] = []
        while pending.count - readOffset >= 4 {
            let typeByte = pending[readOffset]
            let length = (Int(pending[readOffset + 1]) << 16) | (Int(pending[readOffset + 2]) << 8) | Int(pending[readOffset + 3])
            guard pending.count - readOffset >= 4 + length else { break }
            let start = readOffset + 4
            frames.append(CameraFrame(typeByte: typeByte, payload: Data(pending[start..<(start + length)])))
            readOffset = start + length
        }
        // Drop what was read once it is the larger part of the buffer, so it neither grows without end nor is copied for every frame.
        if readOffset > 0, readOffset >= pending.count / 2 {
            pending.removeFirst(readOffset)
            readOffset = 0
        }
        return frames
    }
}

/// CameraStreamEvent is what the frames add up to.
public enum CameraStreamEvent: Equatable, Sendable {
    case codec(String)
    case initSegment(Data)
    /// One complete fragment: `moof` boxes followed by `mdat` boxes.
    case fragment(Data)
}

/// CameraSegmentAssembler joins the frames of one segment into a fragment the
/// way the web player does: everything between a begin and an end frame, with
/// the `moof` parts first, then `mdat`, video and audio parts, in the order
/// they arrived within each kind. The `moof` frame alone is only a header.
public struct CameraSegmentAssembler: Sendable {
    private var moofParts: [Data] = []
    private var mdatParts: [Data] = []
    private var videoParts: [Data] = []
    private var audioParts: [Data] = []

    public init() {}

    public mutating func accept(_ frame: CameraFrame) -> CameraStreamEvent? {
        switch frame.type {
        case .codecInfo:
            return .codec(String(decoding: frame.payload, as: UTF8.self))
        case .initSegment:
            return .initSegment(frame.payload)
        case .beginSegment:
            reset()
        case .moof:
            moofParts.append(frame.payload)
        case .mdat:
            mdatParts.append(frame.payload)
        case .video:
            videoParts.append(frame.payload)
        case .audio:
            audioParts.append(frame.payload)
        case .endSegment:
            var fragment = Data()
            for part in moofParts + mdatParts + videoParts + audioParts { fragment.append(part) }
            reset()
            return fragment.isEmpty ? nil : .fragment(fragment)
        case nil:
            break
        }
        return nil
    }

    private mutating func reset() {
        moofParts = []
        mdatParts = []
        videoParts = []
        audioParts = []
    }
}
