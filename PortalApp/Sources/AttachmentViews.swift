import AVKit
import PortalKit
import QuickLook
import SwiftUI

/// AttachmentImageCache keeps the pictures a session has loaded, so scrolling back shows one at once.
enum AttachmentImageCache {
    nonisolated(unsafe) static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func key(_ connection: Connection, _ id: String) -> NSString { "\(connection.accountKey)|\(id)" as NSString }
}

/// RichBodyView draws text that holds files: the words in between and each file as the web shows it. The same view serves
/// ticket descriptions and comments, chat messages and the assistant's replies.
struct RichBodyView<TextPart: View>: View {
    let markdown: String
    let connection: Connection
    @ViewBuilder let textPart: (String) -> TextPart

    var body: some View {
        let parts = TicketBody.parts(markdown)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text):
                    textPart(text)
                case .attachment(let id, let name, let kind):
                    AttachmentView(attachmentId: id, name: name, kind: kind, connection: connection)
                }
            }
        }
    }
}

extension RichBodyView where TextPart == MarkdownView {
    init(markdown: String, connection: Connection) {
        self.init(markdown: markdown, connection: connection) { MarkdownView(markdown: $0) }
    }
}

/// AttachmentView is one file in a text: a picture inline, a video as a card that plays, any other file as a row.
struct AttachmentView: View {
    let attachmentId: String
    let name: String
    let kind: AttachmentKind
    let connection: Connection

    var body: some View {
        switch kind {
        case .image: AttachmentImage(attachmentId: attachmentId, name: name, connection: connection)
        case .video: AttachmentVideo(attachmentId: attachmentId, name: name, connection: connection)
        case .pdf, .file: AttachmentFileRow(attachmentId: attachmentId, name: name, kind: kind, connection: connection)
        }
    }
}

/// UnavailableAttachmentRow stands in for a file that was deleted or cannot be read. It never shows the token.
private struct UnavailableAttachmentRow: View {
    var body: some View {
        Label("Attachment unavailable", systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AttachmentImage: View {
    let attachmentId: String
    let name: String
    let connection: Connection

    enum Phase {
        case loading
        case loaded(UIImage)
        case unavailable
    }

    @State private var phase = Phase.loading
    @State private var isShowingViewer = false

    var body: some View {
        Group {
            switch phase {
            case .loading:
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { ProgressView() }
            case .loaded(let image):
                Button { isShowingViewer = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(name.isEmpty ? String(localized: "Picture") : name))
                .accessibilityHint(Text("Opens the picture"))
                .fullScreenCover(isPresented: $isShowingViewer) { ImageViewer(image: image, name: name) }
            case .unavailable:
                UnavailableAttachmentRow()
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .task(id: attachmentId) {
            let key = AttachmentImageCache.key(connection, attachmentId)
            if let held = AttachmentImageCache.images.object(forKey: key) {
                phase = .loaded(held)
                return
            }
            guard let data = try? await connection.fetch(path: "/api/v1/attachment/\(attachmentId)"), let image = UIImage(data: data) else {
                phase = .unavailable
                return
            }
            AttachmentImageCache.images.setObject(image, forKey: key)
            phase = .loaded(image)
            // The screenshot run opens the viewer, since a tap cannot be scripted there.
            if DemoOptions.screen == "attachment-viewer" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                isShowingViewer = true
            }
        }
    }
}

/// ImageViewer shows a picture full screen, with pinch zoom, a share button and a close button.
struct ImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let name: String

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ZoomableImage(image: image).ignoresSafeArea()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close")
                Spacer()
                ShareLink(item: Image(uiImage: image), preview: SharePreview(name.isEmpty ? String(localized: "Picture") : name, image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .statusBarHidden()
    }
}

/// ZoomableImage is a picture in a scroll view that pinches and double taps to zoom.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = imageView
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 2.5, animated: true)
        }
    }
}

/// AttachmentVideo is a video as a card with a frame from it when one can be read; a tap plays it in place, with a full screen button.
private struct AttachmentVideo: View {
    let attachmentId: String
    let name: String
    let connection: Connection

    @State private var poster: UIImage?
    @State private var player: AVPlayer?
    @State private var isShowingFullScreen = false
    @State private var isUnavailable = false

    var body: some View {
        Group {
            if isUnavailable {
                UnavailableAttachmentRow()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack {
                        Color.black
                        if let player {
                            VideoPlayer(player: player)
                        } else {
                            if let poster { Image(uiImage: poster).resizable().scaledToFill() }
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 6)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { if player == nil { Task { await play() } } }
                    .accessibilityElement(children: player == nil ? .ignore : .contain)
                    .accessibilityLabel(Text(name.isEmpty ? String(localized: "Video") : name))
                    .accessibilityAddTraits(.isButton)
                    HStack(spacing: 6) {
                        Image(systemName: "video").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(name.isEmpty ? String(localized: "Video") : name).font(.footnote).lineLimit(1)
                        Spacer(minLength: 8)
                        if player != nil {
                            Button { isShowingFullScreen = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.footnote)
                            }
                            .accessibilityLabel("Full screen")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .fullScreenCover(isPresented: $isShowingFullScreen) {
            if let player {
                ZStack(alignment: .topLeading) {
                    VideoPlayer(player: player).ignoresSafeArea()
                    Button { isShowingFullScreen = false } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(12)
                    .accessibilityLabel("Close")
                }
            }
        }
        .task(id: attachmentId) { await loadPoster() }
        .onDisappear { player?.pause() }
    }

    private func asset() async -> AVURLAsset? {
        guard let token = try? await connection.accessToken() else { return nil }
        let url = await connection.server.endpoint("/api/v1/attachment/\(attachmentId)")
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]])
    }

    private func loadPoster() async {
        // The demo server has no real video: its stand-in is a picture, used as the poster.
        if DemoOptions.screen != nil {
            if let data = try? await connection.fetch(path: "/api/v1/attachment/\(attachmentId)"), let image = UIImage(data: data) { poster = image }
            return
        }
        guard let asset = await asset() else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        if let result = try? await generator.image(at: .zero) { poster = UIImage(cgImage: result.image) }
    }

    private func play() async {
        guard let asset = await asset() else {
            isUnavailable = true
            return
        }
        let created = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player = created
        created.play()
    }
}

/// AttachmentFileRow is any other file, a PDF included: an icon and the name. A tap downloads it and opens Quick Look, which can share it.
private struct AttachmentFileRow: View {
    let attachmentId: String
    let name: String
    let kind: AttachmentKind
    let connection: Connection

    @State private var previewURL: URL?
    @State private var isLoading = false
    @State private var isUnavailable = false

    var body: some View {
        if isUnavailable {
            UnavailableAttachmentRow()
        } else {
            Button { Task { await open() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: kind == .pdf ? "doc.richtext" : "doc")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(name.isEmpty ? String(localized: "File") : name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if isLoading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle").foregroundStyle(.secondary) }
                }
                .padding(12)
                .frame(maxWidth: 420)
                .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Downloads and opens the file"))
            .quickLookPreview($previewURL)
        }
    }

    private func open() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await connection.fetch(path: "/api/v1/attachment/\(attachmentId)")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileName = name.isEmpty ? "file" : name.replacingOccurrences(of: "/", with: "-")
            let url = folder.appendingPathComponent(fileName)
            try data.write(to: url)
            previewURL = url
        } catch {
            isUnavailable = true
        }
    }
}
