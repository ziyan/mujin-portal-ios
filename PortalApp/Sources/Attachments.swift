import ImageIO
import Observation
import PhotosUI
import PortalKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// EncodedPicture is a picture ready to attach: the bytes to upload and their format.
struct EncodedPicture: Sendable {
    let data: Data
    let format: AttachmentImageFormat
}

/// PictureEncoder shrinks and recompresses a picture the way AttachmentImages
/// plans it. It works on bytes with ImageIO, so a large camera picture is
/// never held decoded in full, and it is safe to call off the main actor.
enum PictureEncoder {
    static func encode(_ data: Data) -> EncodedPicture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        let sourceFormat = CGImageSourceGetType(source).flatMap { AttachmentImageFormat(typeIdentifier: $0 as String) }
        let plan = AttachmentImages.plan(pixelWidth: width, pixelHeight: height, sourceFormat: sourceFormat, byteCount: data.count)
        if plan.keepsOriginalBytes { return EncodedPicture(data: data, format: plan.outputFormat) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: plan.longestSidePixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        var format = plan.outputFormat
        guard var encoded = render(image, as: format) else { return nil }
        let fallback = AttachmentImages.fallbackFormat(for: format, encodedByteCount: encoded.count)
        if fallback != format, let smaller = render(image, as: fallback) {
            format = fallback
            encoded = smaller
        }
        return EncodedPicture(data: encoded, format: format)
    }

    /// A small picture to show in the composer.
    static func thumbnail(_ data: Data, longestSide: Int = 240) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }

    private static func render(_ image: CGImage, as format: AttachmentImageFormat) -> Data? {
        let output = NSMutableData()
        let type = format == .png ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: AttachmentImages.jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// AttachmentDrafts holds the files a person has picked for a ticket, a
/// comment or a chat message until it is sent. It refuses a file the web app
/// would refuse, before anything is uploaded. A picture is shrunk and
/// recompressed when it is added; each file remembers whether it is waiting,
/// on its way, uploaded or failed, so a retry sends only what is not up yet.
@MainActor
@Observable
final class AttachmentDrafts {
    enum Progress: Equatable {
        case ready
        case uploading
        case uploaded
        case failed
    }

    enum PictureSource {
        case photo
        case pasted
    }

    struct Item: Identifiable {
        let id = UUID()
        let filename: String
        let contentType: String
        let data: Data
        var preview: UIImage?
        var progress = Progress.ready
        var uploadedFile: UploadedFile?
        var isImage: Bool { contentType.lowercased().hasPrefix("image/") }
    }

    private(set) var items: [Item] = []
    /// Pictures being read or shrunk, shown as placeholders.
    private(set) var loadingCount = 0
    /// Why the last pick was refused, in words that name the file.
    var errorText: String?
    var isPickingPhotos = false
    var isTakingPhoto = false
    var isPickingFiles = false
    var photoSelection: [PhotosPickerItem] = []
    private var photoCount = 0
    private var pastedCount = 0

    func add(data: Data, filename: String, contentType: String, preview: UIImage? = nil) {
        if let refusal = AttachmentLimits.refusal(name: filename, byteCount: Int64(data.count), alreadyAttached: items.count) {
            errorText = refusal
            return
        }
        errorText = nil
        let name = AttachmentImages.uniqueName(filename, among: items.map(\.filename))
        items.append(Item(filename: name, contentType: contentType, data: data, preview: preview))
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items = []
        errorText = nil
        photoCount = 0
        pastedCount = 0
    }

    /// Drops the files that reached the server, once the message naming them is sent. Files added while it was going stay.
    func removeUploaded() {
        items.removeAll { $0.progress == .uploaded }
        if items.isEmpty { clear() }
    }

    /// Reads the photos chosen in the picker.
    func loadPhotos() async {
        let chosen = photoSelection
        photoSelection = []
        for pick in chosen {
            loadingCount += 1
            defer { loadingCount -= 1 }
            guard let data = try? await pick.loadTransferable(type: Data.self) else { continue }
            await addPicture(data: data, source: .photo)
        }
    }

    /// Adds a picture's bytes: shrunk to the longest side the composer sends, kept as JPEG or PNG when it was one.
    func addPicture(data: Data, source: PictureSource) async {
        let encoded = await Task.detached(priority: .userInitiated) { PictureEncoder.encode(data) }.value
        guard let encoded else {
            errorText = String(localized: "That picture could not be read.")
            return
        }
        let number: Int
        switch source {
        case .photo:
            photoCount += 1
            number = photoCount
        case .pasted:
            pastedCount += 1
            number = pastedCount
        }
        let label = source == .photo ? String(localized: "Photo \(number)") : String(localized: "Pasted picture \(number)")
        add(
            data: encoded.data, filename: label + "." + encoded.format.fileExtension, contentType: encoded.format.contentType,
            preview: PictureEncoder.thumbnail(encoded.data))
    }

    /// Adds the pictures on the clipboard, if there are any. Used by the Paste picture menu item, which attaches only.
    func pastePicture() {
        Task { _ = await paste(itemProviders: UIPasteboard.general.itemProviders) }
    }

    /// Attaches the pictures among the item providers a Paste or a drop hands over, as many as the message has room
    /// for, each as a placeholder at once and a thumbnail when it is shrunk. Returns the text that came with them
    /// and should be typed into the message, nil when there is none or it only names a picture (see PasteRule).
    func paste(itemProviders: [NSItemProvider]) async -> String? {
        let pictureProviders = itemProviders.filter(PastedPictures.isPicture)
        guard !pictureProviders.isEmpty else { return nil }
        let alreadyAttached = items.count + loadingCount
        let attachable = Array(pictureProviders.prefix(PasteRule.attachableCount(pictureCount: pictureProviders.count, alreadyAttached: alreadyAttached)))
        loadingCount += attachable.count
        let hasLeftOut = attachable.count < pictureProviders.count
        Task {
            for provider in attachable {
                if let data = await PastedPictures.data(from: provider) {
                    await addPicture(data: data, source: .pasted)
                } else {
                    errorText = String(localized: "That picture could not be read.")
                }
                loadingCount -= 1
            }
            if hasLeftOut { errorText = AttachmentLimits.refusal(name: "", byteCount: 0, alreadyAttached: AttachmentLimits.maximumFileCount) }
        }
        var texts: [String] = []
        for provider in itemProviders {
            if let text = await PastedPictures.text(from: provider) { texts.append(text) }
        }
        return PasteRule.decide(
            pictureCount: pictureProviders.count, texts: texts, pictureNames: itemProviders.compactMap(\.suggestedName),
            alreadyAttached: alreadyAttached
        ).textToInsert
    }

    func addFiles(from result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            add(data: data, filename: url.lastPathComponent, contentType: type, preview: type.hasPrefix("image/") ? PictureEncoder.thumbnail(data) : nil)
        }
    }

    /// Uploads every file that is not up yet and returns how to refer to all of them.
    func upload(using connection: Connection) async throws -> [UploadedFile] {
        var uploaded: [UploadedFile] = []
        for item in items {
            if let file = item.uploadedFile {
                uploaded.append(file)
                continue
            }
            setProgress(.uploading, for: item.id)
            do {
                let file = try await connection.uploadAttachment(data: item.data, filename: item.filename, contentType: item.contentType)
                setProgress(.uploaded, for: item.id, file: file)
                uploaded.append(file)
            } catch {
                setProgress(.failed, for: item.id)
                throw error
            }
        }
        return uploaded
    }

    private func setProgress(_ progress: Progress, for id: UUID, file: UploadedFile? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progress = progress
        if let file { items[index].uploadedFile = file }
    }

    /// Fills the composer with invented files for the demo screenshots.
    func stageDemo() {
        let sizes: [(CGSize, UIColor, UIColor)] = [
            (CGSize(width: 480, height: 320), .systemTeal, .systemIndigo),
            (CGSize(width: 320, height: 480), .systemOrange, .systemPink),
        ]
        for (index, spec) in sizes.enumerated() {
            let image = UIGraphicsImageRenderer(size: spec.0).image { context in
                let colors = [spec.1.cgColor, spec.2.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                    context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: spec.0.width, y: spec.0.height), options: [])
                }
            }
            guard let data = image.pngData() else { continue }
            add(data: data, filename: String(localized: "Pasted picture \(index + 1)") + ".png", contentType: "image/png", preview: image)
        }
        add(data: Data(count: 184_000), filename: "Pick list.pdf", contentType: "application/pdf")
    }
}

/// AttachmentPickers installs the three ways to add a file on a screen: the
/// photo library, the camera and Files.
private struct AttachmentPickers: ViewModifier {
    @Bindable var drafts: AttachmentDrafts

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $drafts.isPickingPhotos, selection: $drafts.photoSelection, maxSelectionCount: AttachmentLimits.maximumFileCount, matching: .images)
            .fullScreenCover(isPresented: $drafts.isTakingPhoto) {
                CameraPicker { data in Task { await drafts.addPicture(data: data, source: .photo) } }
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: $drafts.isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                drafts.addFiles(from: result)
            }
            .onChange(of: drafts.photoSelection) { _, selection in
                if !selection.isEmpty { Task { await drafts.loadPhotos() } }
            }
    }
}

extension View {
    func attachmentPickers(_ drafts: AttachmentDrafts) -> some View {
        modifier(AttachmentPickers(drafts: drafts))
    }
}

/// AttachMenu is the button that offers the ways to add a file: the photo
/// library, the camera, Files, and the picture on the clipboard when there is one.
struct AttachMenu: View {
    let drafts: AttachmentDrafts
    var systemImage = "paperclip"

    @State private var hasClipboardPicture = UIPasteboard.general.hasImages

    var body: some View {
        Menu {
            Button {
                drafts.isPickingPhotos = true
            } label: {
                Label("Photo library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    drafts.isTakingPhoto = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }
            Button {
                drafts.isPickingFiles = true
            } label: {
                Label("Files", systemImage: "folder")
            }
            if hasClipboardPicture {
                Button {
                    drafts.pastePicture()
                } label: {
                    Label("Paste picture", systemImage: "doc.on.clipboard")
                }
            }
        } label: {
            Label("Attach", systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: .circle)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityIdentifier("attachMenu")
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            hasClipboardPicture = UIPasteboard.general.hasImages
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            hasClipboardPicture = UIPasteboard.general.hasImages
        }
    }
}

/// AttachmentStrip shows the files picked so far above the field: a picture
/// as a thumbnail, any other file as a chip, each with a button that takes it
/// back. A file on its way shows a spinner; one that failed says so.
struct AttachmentStrip: View {
    let drafts: AttachmentDrafts
    @ScaledMetric(relativeTo: .body) private var thumbnailSide: CGFloat = 64

    var body: some View {
        if !drafts.items.isEmpty || drafts.loadingCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drafts.items) { item in
                        if let preview = item.preview {
                            thumbnail(item, preview: preview)
                        } else {
                            ReferenceChip(
                                systemImage: item.progress == .failed ? "exclamationmark.triangle" : "paperclip", text: item.filename,
                                detail: item.progress == .failed
                                    ? String(localized: "Upload failed")
                                    : ByteCountFormatter.string(fromByteCount: Int64(item.data.count), countStyle: .file)
                            ) { drafts.remove(item) }
                            .opacity(item.progress == .uploading ? 0.5 : 1)
                        }
                    }
                    ForEach(0..<drafts.loadingCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: thumbnailSide, height: thumbnailSide)
                            .overlay { ProgressView() }
                            .accessibilityLabel("Adding a picture")
                    }
                }
            }
            .accessibilityIdentifier("attachmentStrip")
        }
    }

    private func thumbnail(_ item: AttachmentDrafts.Item, preview: UIImage) -> some View {
        Image(uiImage: preview)
            .resizable()
            .scaledToFill()
            .frame(width: thumbnailSide, height: thumbnailSide)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                if item.progress == .uploading {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.35))
                    ProgressView().tint(.white).accessibilityLabel("Uploading")
                } else if item.progress == .failed {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.45))
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white).accessibilityLabel("Upload failed")
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.progress != .uploading {
                    Button {
                        drafts.remove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.title3)
                            .frame(width: 36, height: 36, alignment: .topTrailing)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("Remove \(item.filename)"))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(item.filename))
    }
}

/// CameraPicker takes one photo with the system camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onPhoto: onPhoto, dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPhoto: (Data) -> Void
        let dismiss: () -> Void

        init(onPhoto: @escaping (Data) -> Void, dismiss: @escaping () -> Void) {
            self.onPhoto = onPhoto
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) { onPhoto(data) }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
