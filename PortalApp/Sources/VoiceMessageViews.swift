import PortalKit
import SwiftUI
import UIKit

/// WaveformView draws the 48 bars of a voice message. The bars already played are in the full color. A tap or a drag seeks.
struct WaveformView: View {
    let levels: [Int]
    let progress: Double
    let playedColor: Color
    let restColor: Color
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let played = VoiceMessageRules.playedBarCount(progress: progress, count: count)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let height = max(3, proxy.size.height * CGFloat(level) / CGFloat(VoiceMessageRules.maximumLevel))
                    Capsule()
                        .fill(index < played ? playedColor : restColor)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onSeek?(Double(value.location.x / max(proxy.size.width, 1))) }
                    .onEnded { value in onSeek?(Double(value.location.x / max(proxy.size.width, 1))) }
            )
        }
        .accessibilityHidden(true)
    }
}

/// VoiceMessageBubble is a voice message in a chat: play or pause, the waveform that also seeks, the time left, and a control
/// that shows the words the server heard in it.
struct VoiceMessageBubble: View {
    let messageId: String
    let voice: VoiceMessage
    let isMine: Bool
    let connection: Connection
    let isDemo: Bool
    var isShowingTextAtStart = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingText = false
    @State private var player = VoiceMessagePlayer.shared
    @State private var isBrowserRecording = false

    private var duration: TimeInterval { voice.duration }
    private var position: TimeInterval { player.position(of: messageId) }
    private var isPlaying: Bool { player.playingMessageId == messageId }
    private var isUnplayable: Bool { isBrowserRecording || player.unplayableMessageIds.contains(messageId) }
    private var isUnplayed: Bool { !isMine && !player.hasPlayed(messageId) && !isUnplayable }
    private var progress: Double { duration > 0 ? position / duration : 0 }
    private var timeText: String { isPlaying || position > 0 ? VoiceMessageRules.timeLeftText(duration: duration, position: position) : VoiceMessageRules.clockText(duration) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isUnplayable {
                Label("This recording was made in a browser and cannot be played here. Read the text instead.", systemImage: "speaker.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                playerRow
            }
            HStack(spacing: 8) {
                if isUnplayable {
                    Text(VoiceMessageRules.clockText(duration)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text(timeText).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    if isUnplayed {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("Not played yet")
                    }
                }
                Spacer(minLength: 8)
                if !isUnplayable {
                    Button { isShowingText.toggle() } label: {
                        Text(isShowingText ? "Hide text" : "Show text").font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("voiceShowTextButton")
                }
            }
            if isShowingText || isUnplayable {
                transcript
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 220, alignment: .leading)
        .frame(maxWidth: 360, alignment: .leading)
        .background(
            isMine ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(Color(.secondarySystemBackground)),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .task {
            isShowingText = isShowingTextAtStart
            guard !isMine, let attachmentId = voice.attachmentId else { return }
            let type = await connection.attachmentContentType(id: attachmentId)
            if !VoiceMessageRules.canPlayOnPhone(contentType: type, filename: nil) { isBrowserRecording = true }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var playerRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Button {
                guard let attachmentId = voice.attachmentId else { return }
                player.toggle(messageId: messageId, attachmentId: attachmentId, duration: duration, connection: connection, isDemo: isDemo)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: .circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play voice message")
            .accessibilityIdentifier("voicePlayButton")
            WaveformView(levels: voice.levels, progress: progress, playedColor: Color.accentColor, restColor: Color.secondary.opacity(0.4)) { fraction in
                guard let attachmentId = voice.attachmentId else { return }
                player.seek(
                    messageId: messageId, attachmentId: attachmentId, to: VoiceMessageRules.seekPosition(fraction: fraction, duration: duration), duration: duration,
                    connection: connection, isDemo: isDemo)
            }
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Voice message position")
            .accessibilityValue(Text(timeText))
            .accessibilityAdjustableAction { direction in
                guard let attachmentId = voice.attachmentId else { return }
                let step = direction == .increment ? 5.0 : -5.0
                player.seek(
                    messageId: messageId, attachmentId: attachmentId, to: max(0, min(duration, position + step)), duration: duration, connection: connection,
                    isDemo: isDemo)
            }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        switch voice.transcriptStatus {
        case .text(let words):
            Text(words).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        case .waiting:
            Label("Transcribing\u{2026}", systemImage: "ellipsis").font(.footnote).foregroundStyle(.secondary)
        case .failed:
            Label("Could not transcribe", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// VoiceHoldBar replaces the text box while the composer is in voice mode: press and hold to record, let go to send, slide up to cancel.
struct VoiceHoldBar: View {
    let recorder: VoiceMessageRecorder
    let isEnabled: Bool
    let onKeyboard: () -> Void
    let onStart: () async -> VoiceMessageRecorder.StartResult
    let onFinish: (_ isCancelled: Bool) -> Void

    @State private var isHolding = false
    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 36

    private var diameter: CGFloat { min(scaledDiameter, 60) }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onKeyboard) {
                Image(systemName: "keyboard")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: diameter, height: diameter)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Use the keyboard")
            .accessibilityIdentifier("voiceKeyboardButton")
            holdArea
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.portalCard.opacity(0.92), in: .rect(cornerRadius: 26, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 720 + 32)
        .frame(maxWidth: .infinity)
    }

    private var holdArea: some View {
        ZStack {
            if recorder.isRecording {
                RecordingMeter(recorder: recorder)
            } else {
                Label("Hold to talk", systemImage: "mic.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 8)
        .background(recorder.isCancelling ? Color.statusError.opacity(0.18) : Color(.tertiarySystemFill), in: .capsule)
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isEnabled else { return }
                    if !isHolding {
                        isHolding = true
                        Task {
                            let result = await onStart()
                            if result != .started {
                                isHolding = false
                            } else if !isHolding {
                                // Let go before the recorder was ready: it ends at once and counts as too short.
                                onFinish(false)
                            }
                        }
                    }
                    recorder.follow(upward: Double(-value.translation.height))
                }
                .onEnded { value in
                    guard isHolding else { return }
                    isHolding = false
                    if recorder.isRecording { onFinish(VoiceMessageRules.isCancelling(upward: Double(-value.translation.height))) }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to talk")
        .accessibilityHint("Press and hold to record, and let go to send")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("voiceHoldButton")
    }
}

/// RecordingMeter is what the bar shows while recording: the time, the live bars, and what letting go does.
struct RecordingMeter: View {
    let recorder: VoiceMessageRecorder
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(spacing: 6) {
                Circle().fill(Color.statusError).frame(width: 8, height: 8)
                if let left = recorder.countdownSecondsLeft {
                    Text("\(left) s left").font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Color.statusError)
                } else {
                    Text(VoiceMessageRules.clockText(recorder.elapsed)).font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                WaveformView(
                    levels: recorder.liveAmplitudes.map { Int($0 * Float(VoiceMessageRules.maximumLevel)) }, progress: 1, playedColor: Color.accentColor,
                    restColor: Color.secondary)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity)
            }
            Text(recorder.isCancelling ? "Let go to cancel" : "Slide up to cancel")
                .font(.footnote)
                .foregroundStyle(recorder.isCancelling ? Color.statusError : Color.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

/// VoiceHintView is the short note that tells a quick tap what to do.
struct VoiceHintView: View {
    var body: some View {
        Text("Hold to record, release to send")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect()
            .accessibilityAddTraits(.isStaticText)
    }
}
