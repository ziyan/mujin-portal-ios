import Observation
import PortalKit
import SwiftUI
import UIKit

/// CameraSnapshotCache keeps the last picture of each camera, so a screen opened again shows one at once.
enum CameraSnapshotCache {
    nonisolated(unsafe) static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    static func key(_ camera: Camera, accountKey: String) -> NSString { "\(accountKey)|\(camera.id)" as NSString }
}

/// CameraSnapshotView is a camera's still picture in a 16:9 box, taken again every so often while it is on screen. A camera that cannot be
/// reached shows a crossed-out camera instead and asks for nothing. With no refresh interval it asks once, and only when it holds no picture
/// yet: it is the picture under a tile whose video is about to play.
struct CameraSnapshotView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let camera: Camera
    /// How often a new picture is asked for. The NVR is asked for each one, so this stays slow.
    var refreshInterval: TimeInterval? = 30

    @State private var image: UIImage?
    /// Why the last request for a picture failed, when no picture has come yet. It clears itself when one does.
    @State private var failure: CameraFailure?

    var body: some View {
        Color.black
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                } else if let failure {
                    // A quiet note on the tile, not an alert: a wall of cameras that cannot be reached must not ask for an answer 70 times.
                    VStack(spacing: 4) {
                        Image(systemName: failure == .notAllowed ? "lock" : "video.slash").font(.title3)
                        Text(failure == .notAllowed ? "Not allowed" : "No picture")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(6)
                } else if camera.isStreamable {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "video.slash").font(.title2).foregroundStyle(.white.opacity(0.7))
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: "\(camera.id)|\(refreshInterval == nil)") { await refresh() }
    }

    private func refresh() async {
        let accountKey = session.account.accountKey
        let key = CameraSnapshotCache.key(camera, accountKey: accountKey)
        if image == nil, let held = CameraSnapshotCache.images.object(forKey: key) { image = held }
        guard camera.isStreamable else { return }
        if refreshInterval == nil, image != nil { return }
        let connection = appModel.connection(for: session.account)
        while !Task.isCancelled {
            let path = CameraRoutes.snapshotPath(controllerId: camera.controllerId, cameraId: camera.originCameraId, cacheBust: Int(Date().timeIntervalSince1970))
            do {
                let data = try await connection.fetch(path: path)
                if let picture = UIImage(data: data) {
                    image = picture
                    failure = nil
                    CameraSnapshotCache.images.setObject(picture, forKey: key)
                } else if image == nil {
                    failure = .unavailable
                }
            } catch {
                // A picture already shown stays; a tile that never had one says why, and tries again sooner than a working one refreshes.
                if image == nil, !Task.isCancelled { failure = CameraFailure.classify(error) }
            }
            guard let refreshInterval else { return }
            try? await Task.sleep(for: .seconds(failure == nil ? refreshInterval : min(refreshInterval, 15)))
        }
    }
}

/// CameraWallBudget is how many tiles of one screen play live video at once. A tile asks while at least half of it is on screen and gives its
/// place back when it leaves the screen, so the places are held by tiles that can be seen.
@MainActor
@Observable
final class CameraWallBudget {
    private var streams = CameraWallStreams(limit: UIDevice.current.userInterfaceIdiom == .pad ? CameraWallStreams.tabletLimit : CameraWallStreams.phoneLimit)

    func request(_ cameraId: String) { streams.request(cameraId) }
    func release(_ cameraId: String) { streams.release(cameraId) }
    func fail(_ cameraId: String, isFinal: Bool) { streams.fail(cameraId, isFinal: isFinal) }
    func retain(_ cameraIds: Set<String>) { streams.retain(cameraIds) }
    func hasFailed(_ cameraId: String) -> Bool { streams.hasFailed(cameraId) }
    func isStreaming(_ cameraId: String) -> Bool { streams.isStreaming(cameraId) }
    func isWaiting(_ cameraId: String) -> Bool { streams.isWaiting(cameraId) }
}

/// CameraWaitingChip says a tile that is on screen has no stream yet because the screen's limit of streams is reached. It starts by itself
/// when a stream is free.
private struct CameraWaitingChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.statusWarning).frame(width: 8, height: 8).accessibilityHidden(true)
            Text("Paused").font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6), in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .combine)
    }
}

/// CameraLiveView is a camera's tile picture: live video on the least sharp channel, with the still picture under it while the stream
/// connects. A tile on screen beyond the screen's limit of streams keeps its still, refreshed every so often, with a Paused chip, and
/// starts by itself when a stream is free. Tapping a tile opens the camera, which is where the sharper channels and the recording are.
struct CameraLiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let camera: Camera
    let budget: CameraWallBudget

    @State private var player: CameraPlayer?
    /// Whether the scroll view last said the tile is in view, which outlives the tile leaving the screen under a pushed page.
    @State private var isInView = false
    @State private var isOnScreen = false

    private var isStreaming: Bool { camera.isStreamable && budget.isStreaming(camera.id) }
    /// Whether the stream failed: the tile keeps that state and holds no stream slot.
    private var hasFailed: Bool { camera.isStreamable && budget.hasFailed(camera.id) }
    private var isWaiting: Bool { camera.isStreamable && budget.isWaiting(camera.id) }

    var body: some View {
        CameraSnapshotView(camera: camera, refreshInterval: isStreaming || hasFailed ? nil : 30)
            .overlay {
                if let player, isStreaming || hasFailed {
                    CameraSurface(renderer: player.renderer)
                        .opacity(player.status == .playing ? 1 : 0)
                    if player.status == .failed {
                        failedState(player)
                    } else {
                        VStack {
                            Spacer()
                            HStack {
                                StreamChip(player: player)
                                Spacer()
                            }
                        }
                        .padding(6)
                    }
                } else if isWaiting {
                    VStack {
                        Spacer()
                        HStack {
                            CameraWaitingChip()
                            Spacer()
                        }
                    }
                    .padding(6)
                }
            }
            .clipped()
            .onScrollVisibilityChange(threshold: 0.5) { isVisible in
                isInView = isVisible
                if isVisible { budget.request(camera.id) } else { budget.release(camera.id) }
            }
            // Coming back from a camera's screen moves nothing, so the scroll says nothing: the tile asks again by itself.
            .onAppear {
                isOnScreen = true
                if isInView { budget.request(camera.id) }
            }
            .onDisappear {
                isOnScreen = false
                budget.release(camera.id)
                stopPlayer()
            }
            .onCoveredChange { isCovered in
                guard isOnScreen else { return }
                if isCovered {
                    budget.release(camera.id)
                    stopPlayer()
                } else if isInView {
                    budget.request(camera.id)
                }
            }
            .onChange(of: isStreaming, initial: true) { _, isOn in
                if isOn {
                    if let player { player.retry() } else { startPlayer() }
                } else if !hasFailed {
                    stopPlayer()
                }
            }
            .onChange(of: player?.status) { _, status in
                guard status == .failed, let player else { return }
                budget.fail(camera.id, isFinal: player.isFailureFinal)
            }
            // Only a tile that holds a stream: a failed one keeps its player, and waking it would ask for what was refused, with no slot.
            .onChange(of: scenePhase) { _, phase in
                guard isStreaming else { return }
                if phase == .active { player?.resume() } else { player?.suspend() }
            }
    }

    /// The one state of a tile whose stream failed for good or ran out of retries. A refusal covers the still, which Portal refused too.
    private func failedState(_ player: CameraPlayer) -> some View {
        let isRefused = player.failure == .notAllowed
        return ZStack {
            Color.black.opacity(isRefused ? 1 : 0.55)
            VStack(spacing: 4) {
                Image(systemName: isRefused ? "lock" : "video.slash").font(.title3)
                Text(isRefused ? "Not allowed" : "Unavailable")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(6)
        }
    }

    private func startPlayer() {
        guard player == nil, isStreaming else { return }
        let created = CameraPlayer(
            camera: camera, clock: CameraClock(identifier: camera.timeZone), connection: appModel.connection(for: session.account),
            server: session.account.server, socketFactory: appModel.cameraSocketFactory, isDemo: appModel.isDemo)
        created.quality = CameraWallStreams.tileQuality
        player = created
        created.start(atMS: nil)
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
    }
}

/// CameraStatusText says whether a camera can be watched now.
struct CameraStatusText: View {
    let camera: Camera

    var body: some View {
        if camera.isStreamable {
            Label("Online", systemImage: "circle.fill").labelStyle(CameraDotLabelStyle(color: Color.statusSuccess))
        } else if camera.isControllerConnected == false {
            Label("Controller offline", systemImage: "circle.fill").labelStyle(CameraDotLabelStyle(color: Color.statusError))
        } else {
            Label("Offline", systemImage: "circle.fill").labelStyle(CameraDotLabelStyle(color: Color.statusError))
        }
    }
}

private struct CameraDotLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color).accessibilityHidden(true)
            configuration.title.font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// CameraRow is a camera in a list: a small picture, its name and whether it is online.
struct CameraRow: View {
    let camera: Camera

    var body: some View {
        HStack(spacing: 12) {
            CameraSnapshotView(camera: camera, refreshInterval: 60)
                .frame(width: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.displayName).foregroundStyle(.primary)
                CameraStatusText(camera: camera)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// CameraGridView is every camera of a site as a picture to tap, playing live while the screen is open.
struct CameraGridView: View {
    let model: SiteModel

    @State private var budget = CameraWallBudget()
    @ScaledMetric(relativeTo: .body) private var minimumTileWidth: CGFloat = 170

    var body: some View {
        let onlineCount = model.cameras.filter(\.isStreamable).count
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(onlineCount) of \(model.cameras.count) online")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 12, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(model.cameras) { camera in
                        NavigationLink(value: PortalRoute.camera(CameraTarget(camera: camera))) { CameraTile(camera: camera, budget: budget) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.portalPage)
        .navigationTitle("Cameras")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .onChange(of: model.cameras.map(\.id)) { _, cameraIds in budget.retain(Set(cameraIds)) }
    }
}

/// CameraTile is one camera in the grid.
struct CameraTile: View {
    let camera: Camera
    let budget: CameraWallBudget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CameraLiveView(camera: camera, budget: budget)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(camera.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            CameraStatusText(camera: camera)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// DemoCameraScreens maps a screenshot run's screen name to the camera screen it opens.
enum DemoCameraScreens {
    static func target(for screen: String?, camera: Camera, incidentDetectedAt: Date?) -> CameraTarget? {
        let now = Date().timeIntervalSince1970 * 1000
        switch screen {
        case "camera", "camera-jump", "camera-share", "camera-sound":
            return CameraTarget(camera: camera)
        case "camera-recorded", "camera-unsupported", "camera-unreachable":
            return CameraTarget(camera: camera, startAtMS: now - 25 * 60_000)
        case "camera-incident":
            guard let incidentDetectedAt else { return nil }
            let detected = incidentDetectedAt.timeIntervalSince1970 * 1000
            return CameraTarget(camera: camera, startAtMS: detected - 10_000, markerMS: detected)
        default:
            return nil
        }
    }
}
