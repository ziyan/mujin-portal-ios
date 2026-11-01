import PortalKit
import SwiftUI

/// CameraJumpSheet picks a date and time on the camera's clock to jump to.
struct CameraJumpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let clock: CameraClock
    let onJump: (Double) -> Void

    @State private var picked: Date

    init(clock: CameraClock, initialMS: Double, onJump: @escaping (Double) -> Void) {
        self.clock = clock
        self.onJump = onJump
        _picked = State(initialValue: Date(timeIntervalSince1970: min(initialMS, Date().timeIntervalSince1970 * 1000) / 1000))
    }

    private var pickedMS: Double { picked.timeIntervalSince1970 * 1000 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date and time", selection: $picked, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .environment(\.timeZone, clock.timeZone)
                } footer: {
                    Text(CameraText.zoneCaption(pickedMS, clock: clock))
                }
                Section("Time of day") {
                    block("Night", CameraDayJump.night, systemImage: "moon.stars")
                    block("Morning", CameraDayJump.morning, systemImage: "sunrise")
                    block("Afternoon", CameraDayJump.afternoon, systemImage: "sun.max")
                    block("Evening", CameraDayJump.evening, systemImage: "sunset")
                }
                Section("Back from now") {
                    ago("10 minutes ago", minutes: 10)
                    ago("1 hour ago", minutes: 60)
                    ago("Yesterday", minutes: 24 * 60)
                    ago("1 week ago", minutes: 7 * 24 * 60)
                }
            }
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        onJump(pickedMS)
                        dismiss()
                    }
                    .accessibilityIdentifier("cameraJumpGo")
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Moves the picked time to the start of a part of the picked day, on the camera's calendar.
    private func block(_ title: LocalizedStringKey, _ block: CameraDayJump.Block, systemImage: String) -> some View {
        Button {
            let dayStart = CameraDayJump.dayStartMS(containing: pickedMS, in: clock.timeZone)
            let target = CameraDayJump.target(dayStartMS: dayStart, block: block, in: clock.timeZone, nowMS: Date().timeIntervalSince1970 * 1000)
            picked = Date(timeIntervalSince1970: target / 1000)
        } label: {
            Label(title, systemImage: systemImage).foregroundStyle(.primary)
        }
    }

    private func ago(_ title: LocalizedStringKey, minutes: Double) -> some View {
        Button {
            picked = Date().addingTimeInterval(-minutes * 60)
        } label: {
            Label(title, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
        }
    }
}

/// CameraShareSheet cuts a clip out of the recording and hands it to the share sheet. The clip is prepared first, since the NVR makes the file
/// when it is asked for.
struct CameraShareSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    let camera: Camera
    let clock: CameraClock
    let playheadMS: Double
    let channel: Int

    enum Phase: Equatable {
        case choosing
        case preparing
        case ready(URL)
        case failed(String)
    }

    @State private var lengthMS = 60_000.0
    @State private var phase = Phase.choosing

    private var clip: CameraClip {
        CameraClip(aroundMS: playheadMS, lengthMS: lengthMS, nowMS: Date().timeIntervalSince1970 * 1000)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Length", selection: $lengthMS) {
                        Text("30 sec").tag(30_000.0)
                        Text("1 min").tag(60_000.0)
                        Text("5 min").tag(300_000.0)
                        Text("15 min").tag(900_000.0)
                        Text("30 min").tag(1_800_000.0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(phase == .preparing)
                } footer: {
                    Text("The clip starts 10 seconds before the picture on screen.")
                }
                Section {
                    LabeledContent("From") { Text(CameraText.stamp(clip.startMS, clock: clock)).monospacedDigit() }
                    LabeledContent("To") { Text(CameraText.stamp(clip.endMS, clock: clock)).monospacedDigit() }
                } footer: {
                    Text(CameraText.zoneCaption(clip.startMS, clock: clock))
                }
                Section {
                    switch phase {
                    case .choosing:
                        Button { Task { await prepare() } } label: { Label("Prepare clip", systemImage: "film") }
                            .accessibilityIdentifier("cameraPrepareClip")
                    case .preparing:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Preparing the clip")
                        }
                    case .ready(let url):
                        ShareLink(item: url) { Label("Share clip", systemImage: "square.and.arrow.up") }
                    case .failed(let message):
                        Text(message).foregroundStyle(Color.statusError)
                        Button("Try again") { Task { await prepare() } }
                    }
                }
            }
            .navigationTitle("Share a clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onChange(of: lengthMS) { _, _ in phase = .choosing }
        }
        .presentationDetents([.medium, .large])
        .task {
            if appModel.isDemo, DemoOptions.screen == "camera-share" {
                try? await Task.sleep(nanoseconds: 800_000_000)
                await prepare()
            }
        }
    }

    private func prepare() async {
        phase = .preparing
        let connection = appModel.connection(for: session.account)
        let selected = clip
        // A selection is at most one export long, so this is a single clip.
        let path = CameraRoutes.exportPath(
            controllerId: camera.controllerId, cameraId: camera.originCameraId, channel: channel, startMS: selected.startMS, endMS: selected.endMS, isDownload: true)
        do {
            let download = try await CameraFiles.download(path: path, connection: connection, isDemo: appModel.isDemo, startMS: selected.startMS)
            // The file is renamed to say which camera and moment it is, since that is the name the person sees when it is saved.
            let named = download.url.deletingLastPathComponent().appendingPathComponent(
                CameraFiles.fileName(cameraName: camera.displayName, startMS: selected.startMS, clock: clock))
            try? FileManager.default.removeItem(at: named)
            try FileManager.default.moveItem(at: download.url, to: named)
            phase = .ready(named)
        } catch {
            phase = .failed(error.userMessage)
            appModel.handle(error, account: session.account)
        }
    }
}
