import PortalKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// ShareViewController is the share extension: it copies what was shared
/// into the app group (never decoding a whole image), then shows ShareView.
final class ShareViewController: UIViewController {
    private let backend = LiveShareBackend()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { @MainActor in
            let jobId = UUID().uuidString
            let loaded = await SharedContentLoader.load(
                from: (extensionContext?.inputItems as? [NSExtensionItem]) ?? [], into: backend.store.directory(forJob: jobId))
            if backend.accounts.isEmpty {
                showMessage(String(localized: "Open Portal and sign in first."))
                return
            }
            let model = ShareModel(backend: backend, jobId: jobId, text: loaded.text, files: loaded.files, skippedMessages: loaded.skippedMessages)
            let host = UIHostingController(
                rootView: ShareView(
                    model: model,
                    onFinish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                    onCancel: { [weak self] in
                        if model.phase != .sending { self?.backend.discard(jobId: jobId) }
                        self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                    }))
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        })
        present(alert, animated: true)
    }
}

/// SharedContentLoader reads the items the share sheet hands over.
enum SharedContentLoader {
    struct Loaded {
        var text = ""
        var files: [SharedFile] = []
        var skippedMessages: [String] = []
    }

    static func load(from items: [NSExtensionItem], into folder: URL) async -> Loaded {
        var texts: [String] = []
        var urls: [URL] = []
        var loaded = Loaded()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in items {
            if let title = item.attributedContentText?.string, !title.isEmpty { texts.append(title) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || isFile(provider) {
                    await copyFile(from: provider, into: folder, loaded: &loaded)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { urls.append(url) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { texts.append(text) }
                }
            }
        }
        // The title some apps add is usually the same as the address or the text.
        var uniqueTexts: [String] = []
        for text in texts where !uniqueTexts.contains(text) && !urls.contains(where: { $0.absoluteString == text }) { uniqueTexts.append(text) }
        loaded.text = SharePayload.combinedText(texts: uniqueTexts, urls: urls)
        return loaded
    }

    /// An image, a movie, a PDF or any other file, as opposed to text and web addresses.
    private static func isFile(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .movie) || type.conforms(to: .audio)
                || (type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url))
        }
    }

    /// Copies a file into the job's folder from where the system put it. The
    /// copy is made on disk, so the file is never read into memory.
    private static func copyFile(from provider: NSItemProvider, into folder: URL, loaded: inout Loaded) async {
        let identifier =
            provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .data) == true }
            ?? UTType.data.identifier
        let type = UTType(identifier)
        let copied: (URL, String)? = await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let storedName = UUID().uuidString
                do {
                    try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(storedName))
                    continuation.resume(returning: (url, storedName))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let (original, storedName) = copied else {
            loaded.skippedMessages.append(String(localized: "A file could not be read."))
            return
        }
        let stored = folder.appendingPathComponent(storedName)
        let size = (try? FileManager.default.attributesOfItem(atPath: stored.path)[.size] as? Int64) ?? 0
        let suggested = provider.suggestedName ?? original.deletingPathExtension().lastPathComponent
        let fileExtension = type?.preferredFilenameExtension ?? original.pathExtension
        let filename = fileExtension.isEmpty || suggested.lowercased().hasSuffix("." + fileExtension.lowercased()) ? suggested : suggested + "." + fileExtension
        if size > SharePayload.maximumFileBytes {
            try? FileManager.default.removeItem(at: stored)
            loaded.skippedMessages.append(String(localized: "\(filename) is larger than 32 MB and was left out."))
            return
        }
        loaded.files.append(
            SharedFile(
                id: UUID().uuidString, filename: filename, contentType: type?.preferredMIMEType ?? "application/octet-stream", storedName: storedName,
                byteCount: size, thumbnailData: type?.conforms(to: .image) == true ? Thumbnail.data(for: stored) : nil))
    }
}
