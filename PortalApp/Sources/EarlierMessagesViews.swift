import PortalKit
import SwiftUI

/// EarlierMessagesRow sits at the top of a chat or conversation and says what is before the first message held: that a pull down
/// reads more, with an arrow that turns as the pull reaches the set distance, a spinner while it reads, why it failed with a way to
/// try again, or that this is the start. VoiceOver reads it as a button that loads the earlier messages.
struct EarlierMessagesRow: View {
    let state: EarlierMessages.RowState
    /// How far the pull has gone toward reading more, from 0 to 1.
    let pullProgress: Double
    let onLoad: () -> Void

    var body: some View {
        Group {
            switch state {
            case .more:
                let isArmed = pullProgress >= 1
                Label {
                    Text(isArmed ? LocalizedStringKey("Release to load earlier messages") : LocalizedStringKey("Pull down for earlier messages"))
                } icon: {
                    Image(systemName: "arrow.down")
                        .rotationEffect(.degrees(isArmed ? 180 : 0))
                        .animation(.easeOut(duration: 0.15), value: isArmed)
                }
                .foregroundStyle(.secondary)
                .opacity(0.6 + 0.4 * pullProgress)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading earlier messages…").foregroundStyle(.secondary)
                }
            case .failed(let reason):
                VStack(spacing: 6) {
                    Label("Earlier messages could not be loaded.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    if !reason.isEmpty {
                        Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button("Try again", action: onLoad)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("earlierMessagesRetry")
                }
            case .start:
                Text("Start of the conversation").foregroundStyle(.tertiary)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 4)
        // One element that reads its words, except after a failure, where the button to try again stays its own.
        .accessibilityElement(children: state.canLoad && state != .more ? .contain : .combine)
        .accessibilityValue(Text(verbatim: state.name))
        .accessibilityIdentifier("earlierMessagesRow")
        .accessibilityAction(named: Text("Load earlier messages")) { if state.canLoad { onLoad() } }
    }
}

/// PullForEarlier reads how far the person pulls a list past its top, and reads earlier messages when they let go past the set
/// distance, with a light tap as the pull arms. Reaching the top alone reads nothing.
struct PullForEarlier: ViewModifier {
    let state: EarlierMessages.RowState
    @Binding var pullProgress: Double
    let onLoad: () -> Void

    @State private var isArmed = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Double.self) { geometry in
                max(0, -Double(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, overscroll in
                let progress = state.canLoad ? EarlierMessages.pullProgress(overscroll: overscroll) : 0
                if abs(progress - pullProgress) > 0.01 || (progress == 0) != (pullProgress == 0) { pullProgress = progress }
                let armed = EarlierMessages.isArmed(overscroll: overscroll, state: state)
                if armed != isArmed { isArmed = armed }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                // Letting go of an armed pull reads the earlier page.
                if oldPhase == .interacting, newPhase != .interacting, isArmed {
                    isArmed = false
                    onLoad()
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isArmed) { _, armed in armed }
    }
}
