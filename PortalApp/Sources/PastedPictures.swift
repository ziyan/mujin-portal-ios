import UIKit
import UniformTypeIdentifiers

/// PastedPictures reads pictures and text out of the item providers that a
/// Paste or a drop hands over. A picture may arrive as bytes (PNG, JPEG, HEIC,
/// GIF), as a file the Files app or Photos copied, or only as an object that can
/// become a UIImage; every one of those counts. Which items become attachments,
/// and whether the text beside them is typed, is PasteRule's decision.
enum PastedPictures {
    /// Formats tried first, so a provider that offers the same picture twice is read in the one the composer keeps.
    private static let preferredTypes: [UTType] = [.jpeg, .png, .heic, .heif, .gif]

    /// The type to read a provider's picture as; nil when it offers no picture type. SVG is not a picture the composer can shrink.
    static func pictureType(of provider: NSItemProvider) -> String? {
        let types = provider.registeredTypeIdentifiers.compactMap { identifier in
            UTType(identifier).map { (identifier: identifier, type: $0) }
        }
        let pictures = types.filter { $0.type.conforms(to: .image) && !$0.type.conforms(to: .svg) }
        for preferred in preferredTypes {
            if let match = pictures.first(where: { $0.type == preferred }) { return match.identifier }
        }
        return pictures.first?.identifier
    }

    static func isPicture(_ provider: NSItemProvider) -> Bool {
        pictureType(of: provider) != nil || provider.canLoadObject(ofClass: UIImage.self)
    }

    /// The picture's bytes in the format it was copied with, or PNG bytes when it can only be read as an image object.
    @MainActor
    static func data(from provider: NSItemProvider) async -> Data? {
        if let identifier = pictureType(of: provider) {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in continuation.resume(returning: data) }
            }
            if let data { return data }
        }
        guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in continuation.resume(returning: (object as? UIImage)?.pngData()) }
        }
    }

    /// The text a provider carries, if any.
    @MainActor
    static func text(from provider: NSItemProvider) async -> String? {
        guard provider.canLoadObject(ofClass: String.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }
    }
}
