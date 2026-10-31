import Observation
import PhotosUI
import PortalKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// AttachmentDrafts holds the files a person has picked for a ticket or a
/// comment until it is sent. It refuses a file the web app would refuse,
/// before anything is uploaded.
@MainActor
@Observable
final class AttachmentDrafts {
    struct Item: Identifiable {
        let id = UUID()
        let filename: String
        let contentType: String
        let data: Data
        var isImage: Bool { contentType.lowercased().hasPrefix("image/") }
    }

    private(set) var items: [Item] = []
    /// Why the last pick was refused, in words that name the file.
    var errorText: String?
    var isPickingPhotos = false
    var isTakingPhoto = false
    var isPickingFiles = false
    var photoSelection: [PhotosPickerItem] = []
    private var photoCount = 0

    func add(data: Data, filename: String, contentType: String) {
        if let refusal = AttachmentLimits.refusal(name: filename, byteCount: Int64(data.count), alreadyAttached: items.count) {
            errorText = refusal
            return
        }
        errorText = nil
        items.append(Item(filename: filename, contentType: contentType, data: data))
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items = []
        errorText = nil
    }

    /// Reads the photos chosen in the picker. Anything but JPEG and PNG is
    /// saved as JPEG, which every screen can show.
    func loadPhotos() async {
        let chosen = photoSelection
        photoSelection = []
        for pick in chosen {
            guard let data = try? await pick.loadTransferable(type: Data.self) else { continue }
            let isPlain = pick.supportedContentTypes.contains { $0.conforms(to: .jpeg) || $0.conforms(to: .png) }
            addPhoto(data: data, keepsFormat: isPlain, isPNG: pick.supportedContentTypes.contains { $0.conforms(to: .png) })
        }
    }

    func addPhoto(data: Data, keepsFormat: Bool, isPNG: Bool = false) {
        photoCount += 1
        if keepsFormat {
            add(data: data, filename: String(localized: "Photo \(photoCount)") + (isPNG ? ".png" : ".jpg"), contentType: isPNG ? "image/png" : "image/jpeg")
        } else if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
            add(data: jpeg, filename: String(localized: "Photo \(photoCount)") + ".jpg", contentType: "image/jpeg")
        }
    }

    func addFiles(from result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            add(data: data, filename: url.lastPathComponent, contentType: type)
        }
    }

    /// Uploads every file and returns how to refer to them.
    func upload(using connection: Connection) async throws -> [UploadedFile] {
        var uploaded: [UploadedFile] = []
        for item in items {
            uploaded.append(try await connection.uploadAttachment(data: item.data, filename: item.filename, contentType: item.contentType))
        }
        return uploaded
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
                CameraPicker { data in drafts.addPhoto(data: data, keepsFormat: false) }
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

/// AttachMenu is the button that offers the ways to add a file.
struct AttachMenu: View {
    let drafts: AttachmentDrafts

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
                    Label("Take a photo", systemImage: "camera")
                }
            }
            Button {
                drafts.isPickingFiles = true
            } label: {
                Label("Choose a file", systemImage: "doc")
            }
        } label: {
            Label("Attach", systemImage: "paperclip")
        }
        .accessibilityIdentifier("attachMenu")
    }
}

/// AttachmentStrip shows the files picked so far, each with a way to take it back.
struct AttachmentStrip: View {
    let drafts: AttachmentDrafts

    var body: some View {
        if !drafts.items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drafts.items) { item in
                        HStack(spacing: 6) {
                            if item.isImage, let image = UIImage(data: item.data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .accessibilityHidden(true)
                            } else {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            Text(item.filename)
                                .font(.footnote)
                                .lineLimit(1)
                            Button {
                                drafts.remove(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove \(item.filename)"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
            }
        }
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
