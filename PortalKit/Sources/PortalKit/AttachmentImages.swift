import Foundation

/// AttachmentImageFormat is a picture format the composer keeps as it is.
/// Anything else (HEIC, GIF, TIFF) is sent as JPEG, which every screen shows.
public enum AttachmentImageFormat: Equatable, Sendable {
    case jpeg
    case png

    public var contentType: String {
        switch self {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        }
    }

    /// The format for a uniform type identifier such as `public.png`; nil for one that is not kept.
    public init?(typeIdentifier: String) {
        switch typeIdentifier.lowercased() {
        case "public.jpeg", "public.jpg": self = .jpeg
        case "public.png": self = .png
        default: return nil
        }
    }
}

/// AttachmentImagePlan is what to do with a picture before it is attached.
public struct AttachmentImagePlan: Equatable, Sendable {
    /// The longest side the picture is sent at, in pixels.
    public let longestSidePixels: Int
    public let outputFormat: AttachmentImageFormat
    /// True when the bytes are sent exactly as they came, with no decode and encode.
    public let keepsOriginalBytes: Bool
}

/// AttachmentImages decides how a picture is sized, formatted and named. The
/// pixels themselves are drawn by the app; every decision is here so it can be tested.
public enum AttachmentImages {
    /// The longest side a picture is sent at: plenty to read a receipt or a
    /// screen, and a fraction of what a camera takes.
    public static let longestSidePixels = 2048
    public static let jpegQuality = 0.8

    /// How to send a picture of the given size. A JPEG or PNG that already
    /// fits, in bytes and in pixels, goes up untouched; a larger one is
    /// scaled down and kept in its format; any other format becomes JPEG.
    public static func plan(pixelWidth: Int, pixelHeight: Int, sourceFormat: AttachmentImageFormat?, byteCount: Int) -> AttachmentImagePlan {
        let longestSide = max(pixelWidth, pixelHeight)
        let isSmallEnough = longestSide <= longestSidePixels
        let isLightEnough = Int64(byteCount) <= AttachmentLimits.maximumFileBytes
        if let sourceFormat, isSmallEnough, isLightEnough {
            return AttachmentImagePlan(longestSidePixels: longestSide, outputFormat: sourceFormat, keepsOriginalBytes: true)
        }
        return AttachmentImagePlan(
            longestSidePixels: min(longestSide, longestSidePixels), outputFormat: sourceFormat ?? .jpeg, keepsOriginalBytes: false)
    }

    /// The format to fall back to when a re-encoded picture is still over the size limit: a PNG becomes a JPEG.
    public static func fallbackFormat(for format: AttachmentImageFormat, encodedByteCount: Int) -> AttachmentImageFormat {
        format == .png && Int64(encodedByteCount) > AttachmentLimits.maximumFileBytes ? .jpeg : format
    }

    /// The size a picture is drawn at: both sides scaled by the same factor, none under one pixel.
    public static func fittedSize(pixelWidth: Int, pixelHeight: Int) -> (width: Int, height: Int) {
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > longestSidePixels else { return (pixelWidth, pixelHeight) }
        let factor = Double(longestSidePixels) / Double(longestSide)
        return (max(1, Int((Double(pixelWidth) * factor).rounded())), max(1, Int((Double(pixelHeight) * factor).rounded())))
    }

    /// A name that no file in `existingNames` has: `name.ext`, then `name 2.ext`, `name 3.ext`.
    public static func uniqueName(_ name: String, among existingNames: [String]) -> String {
        let taken = Set(existingNames.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var base = name
        var fileExtension = ""
        if let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex {
            base = String(name[..<dot])
            fileExtension = String(name[name.index(after: dot)...])
        }
        var number = 2
        while true {
            let candidate = fileExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(fileExtension)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }
}

extension AttachmentLimits {
    /// Why a set of files cannot be sent as a message: the text with its attachment links would be too long for a chat message.
    public static func chatMessageRefusal(text: String, files: [UploadedFile]) -> String? {
        let message = SharePayload.assistantMessage(text: text, files: files)
        guard message.count > ChatRules.maximumMessageCharacters else { return nil }
        return "A message can be up to \(ChatRules.maximumMessageCharacters) characters."
    }
}
