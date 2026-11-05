import PortalKit
import SwiftUI
import UIKit

/// CameraDetailView is one camera: the picture, live or from the recording, a
/// timeline to scrub back into it, and the controls to play, pause, change
/// speed, jump to a date, return to live and share a clip. Turned to landscape
/// on a phone, the picture fills the screen.
struct CameraDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    let target: CameraTarget

    @State private var player: CameraPlayer?
    @State private var spanMS = CameraTimeline.hourMS
    @State private var scrubMS: Double?
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var isShowingJump = false
    @State private var isShowingShare = false
    @State private var areControlsHidden = false

    private var isLandscapePhone: Bool { verticalSizeClass == .compact }

    var body: some View {
        Group {
            if let player {
                if isLandscapePhone { landscape(player) } else { portrait(player) }
            } else {
                ProgressView()
            }
        }
        .background(isLandscapePhone ? Color.black : Color.portalPage)
        .navigationTitle(target.camera.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(isLandscapePhone ? .hidden : .automatic, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .statusBarHidden(isLandscapePhone)
        .toolbar {
            if let player {
                if !player.qualitiesOffered.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { CameraQualityMenu(player: player) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingShare = true } label: { Label("Share a clip", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("cameraShareButton")
                }
            }
        }
        .sheet(isPresented: $isShowingJump) {
            if let player {
                CameraJumpSheet(clock: player.clock, initialMS: scrubMS ?? player.playheadMS) { timeMS in
                    scrubMS = nil
                    player.seek(toMS: timeMS)
                }
            }
        }
        .sheet(isPresented: $isShowingShare) {
            if let player {
                CameraShareSheet(camera: target.camera, clock: player.clock, playheadMS: player.playheadMS, channel: player.channel)
            }
        }
        .task { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: player?.resume()
            case .inactive, .background: player?.suspend()
            @unknown default: break
            }
        }
        .onCoveredChange { isCovered in
            if isCovered { player?.suspend() } else { player?.resume() }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AppDelegate.allowsLandscape = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            AppDelegate.allowsLandscape = false
            player?.stop()
        }
    }

    private func prepare() async {
        guard player == nil else { return }
        let connection = appModel.connection(for: session.account)
        let created = CameraPlayer(
            camera: target.camera, clock: CameraClock(identifier: target.camera.timeZone), connection: connection, server: session.account.server,
            socketFactory: appModel.cameraSocketFactory, isDemo: appModel.isDemo)
        player = created
        created.start(atMS: target.startAtMS)
        // A camera whose registry row has no zone gets the NVR's own, from its bootstrap document.
        if target.camera.timeZone == nil, let identifier = await connection.nvrTimeZone(controllerId: target.camera.controllerId) {
            created.updateClock(CameraClock(identifier: identifier))
        }
        if appModel.isDemo {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if DemoOptions.screen == "camera-jump" { isShowingJump = true }
            if DemoOptions.screen == "camera-share" { isShowingShare = true }
            if DemoOptions.screen == "camera-sound" { created.toggleSound() }
        }
    }

    // MARK: portrait

    private func portrait(_ player: CameraPlayer) -> some View {
        VStack(spacing: 0) {
            video(player).aspectRatio(16 / 9, contentMode: .fit)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    timeHeader(player)
                    timeline(player)
                    Picker("Zoom", selection: $spanMS) {
                        Text("15 min").tag(15 * CameraTimeline.minuteMS)
                        Text("1 hr").tag(CameraTimeline.hourMS)
                        Text("4 hr").tag(4 * CameraTimeline.hourMS)
                        Text("24 hr").tag(CameraTimeline.dayMS)
                    }
                    .pickerStyle(.segmented)
                    transport(player)
                    if let notice = player.notice, player.status != .failed {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    private func timeHeader(_ player: CameraPlayer) -> some View {
        let shownMS = scrubMS ?? player.playheadMS
        return VStack(alignment: .leading, spacing: 2) {
            Text(CameraText.stamp(shownMS, clock: player.clock))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(CameraText.zoneCaption(shownMS, clock: player.clock))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func timeline(_ player: CameraPlayer) -> some View {
        CameraTimelineView(
            centerMS: scrubMS ?? player.playheadMS, spanMS: $spanMS, nowMS: Date().timeIntervalSince1970 * 1000, markerMS: target.markerMS, clock: player.clock,
            onScrub: { scrubMS = $0 },
            onCommit: { timeMS in
                scrubMS = nil
                player.seek(toMS: timeMS)
            })
    }

    private func transport(_ player: CameraPlayer) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 28) {
                // The sound button sits to the right of the other three; the same width on the left keeps them centered.
                if player.hasSound { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
                Button { player.skip(byMS: -10_000) } label: {
                    Image(systemName: "gobackward.10").font(.title2).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back 10 seconds")
                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill").font(.largeTitle).frame(minWidth: 56, minHeight: 56)
                }
                .accessibilityLabel(player.isPaused ? Text("Play") : Text("Pause"))
                .accessibilityIdentifier("cameraPlayPause")
                Button { player.skip(byMS: 10_000) } label: {
                    Image(systemName: "goforward.10").font(.title2).frame(minWidth: 44, minHeight: 44)
                }
                .disabled(player.isLive)
                .accessibilityLabel("Forward 10 seconds")
                if player.hasSound { SoundButton(player: player) }
            }
            .buttonStyle(.plain)
            // Four icons side by side must fit the width at the largest text sizes, so the row stops growing a step short of them.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { secondaryControls(player) }
                VStack(spacing: 10) { secondaryControls(player) }
            }
        }
    }

    @ViewBuilder
    private func secondaryControls(_ player: CameraPlayer) -> some View {
        Menu {
            Picker("Speed", selection: Binding(get: { player.speed }, set: { player.setSpeed($0) })) {
                ForEach(CameraSpeed.rates, id: \.self) { rate in Text("\(rate.formatted())×").tag(rate) }
            }
        } label: {
            Label("\(player.speed.formatted())×", systemImage: "speedometer").frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .disabled(player.isLive)
        Button { isShowingJump = true } label: {
            Label("Jump to", systemImage: "calendar").frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("cameraJumpButton")
        Button { scrubMS = nil; player.goLive() } label: {
            Label("Live", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .disabled(player.isLive && !player.isPaused)
        .accessibilityIdentifier("cameraLiveButton")
    }

    // MARK: the picture

    private func video(_ player: CameraPlayer) -> some View {
        ZStack {
            Color.black
            CameraSurface(renderer: player.renderer)
                .scaleEffect(zoom)
                .offset(pan)
            statusOverlay(player)
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .onChanged { value in zoom = min(max(zoomBase * value.magnification, 1), 6) }
                .onEnded { _ in
                    zoomBase = zoom
                    if zoom <= 1.01 { resetZoom() }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard zoom > 1 else { return }
                    pan = CGSize(width: panBase.width + value.translation.width, height: panBase.height + value.translation.height)
                }
                .onEnded { _ in panBase = pan }
        )
        .onTapGesture(count: 2) { withAnimation { resetZoom() } }
        .onTapGesture { if isLandscapePhone { withAnimation { areControlsHidden.toggle() } } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(target.camera.displayName))
    }

    private func resetZoom() {
        zoom = 1
        zoomBase = 1
        pan = .zero
        panBase = .zero
    }

    @ViewBuilder
    private func statusOverlay(_ player: CameraPlayer) -> some View {
        ZStack {
            switch player.status {
            case .connecting:
                ProgressView().tint(.white)
            case .reconnecting, .stalled:
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Reconnecting").font(.footnote).foregroundStyle(.white)
                }
            case .failed:
                VStack(spacing: 10) {
                    Image(systemName: "video.slash").font(.title).foregroundStyle(.white.opacity(0.8))
                    Text(player.notice ?? String(localized: "The camera could not be reached."))
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if player.isRecordingUnsupported {
                        Button("Download clip") { isShowingShare = true }.buttonStyle(.borderedProminent)
                    } else if player.camera.isStreamable || !player.isLive {
                        Button("Try again") { player.retry() }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
                // The picture is a fixed 16 by 9, so its message stops growing with the text size before it would be cut off.
                .dynamicTypeSize(...DynamicTypeSize.large)
            case .ended:
                Text(player.notice ?? "").font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center).padding(16)
            case .idle, .playing:
                EmptyView()
            }
            VStack {
                HStack {
                    StreamChip(player: player)
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
    }

    // MARK: landscape

    private func landscape(_ player: CameraPlayer) -> some View {
        ZStack {
            video(player).ignoresSafeArea()
            if !areControlsHidden {
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Close")
                        Spacer()
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button { player.togglePause() } label: {
                            Image(systemName: player.isPaused ? "play.fill" : "pause.fill").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel(player.isPaused ? Text("Play") : Text("Pause"))
                        if player.hasSound {
                            Button { player.toggleSound() } label: {
                                Image(systemName: player.isSoundOn ? "speaker.wave.2" : "speaker.slash").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel(player.isSoundOn ? Text("Mute") : Text("Unmute"))
                            .accessibilityIdentifier("cameraSound")
                        }
                        Text(CameraText.stamp(player.playheadMS, clock: player.clock) + " " + player.clock.zoneLabel(atMS: player.playheadMS))
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                        Spacer()
                        Button { player.goLive() } label: {
                            Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.body.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .disabled(player.isLive && !player.isPaused)
                    }
                }
                .foregroundStyle(.white)
                .padding(12)
            }
        }
    }
}

/// SoundButton turns the camera's sound on and off. Sound starts off.
struct SoundButton: View {
    let player: CameraPlayer

    var body: some View {
        Button { player.toggleSound() } label: {
            Image(systemName: player.isSoundOn ? "speaker.wave.2" : "speaker.slash").font(.title2).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(player.isSoundOn ? Text("Mute") : Text("Unmute"))
        .accessibilityIdentifier("cameraSound")
    }
}

/// StreamChip says what the picture is and how the stream is doing.
struct StreamChip: View {
    let player: CameraPlayer

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6), in: Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .combine)
    }

    /// "Offline" only for a camera or controller that is offline. An online camera whose video failed says what kind of failure it was.
    private var failedText: LocalizedStringKey {
        if player.isRecordingUnsupported { return "No recording" }
        if !player.camera.isStreamable { return "Offline" }
        return player.failure == .notAllowed ? "Not allowed" : "Unavailable"
    }

    private var text: LocalizedStringKey {
        switch player.status {
        case .stalled: "No data"
        case .reconnecting: "Reconnecting"
        case .failed: failedText
        case .connecting, .idle: player.isLive ? "Connecting" : "Loading"
        case .ended: "No recording"
        case .playing: player.isPaused ? "Paused" : (player.isLive ? "Live" : "Recorded")
        }
    }

    private var color: Color {
        switch player.status {
        case .playing: player.isLive && !player.isPaused ? Color.statusError : Color.statusInfo
        case .stalled, .reconnecting, .connecting, .idle: Color.statusWarning
        case .failed, .ended: Color.gray
        }
    }
}

/// CameraQualityMenu picks which of the camera's streams to watch.
struct CameraQualityMenu: View {
    @Bindable var player: CameraPlayer

    var body: some View {
        Menu {
            Picker("Quality", selection: $player.quality) {
                ForEach(player.qualitiesOffered, id: \.self) { quality in
                    switch quality {
                    case .low: Text("Low").tag(quality)
                    case .medium: Text("Medium").tag(quality)
                    case .high: Text("High").tag(quality)
                    }
                }
            }
        } label: {
            Label("Quality", systemImage: "dial.medium")
        }
    }
}
