import PortalKit
import SwiftUI

/// BackgroundCommandsSheet lists the shell commands the assistant runs in the background in this view, the main history or one
/// thread: each command, its state, how long it has run and the newest of its output. Its owner may stop one that runs.
struct BackgroundCommandsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ConversationModel
    let currentUserId: String

    var body: some View {
        NavigationStack {
            Group {
                if model.shownBackgroundCommands.isEmpty {
                    ContentUnavailableView("No background commands", systemImage: "apple.terminal")
                } else {
                    // One clock for the sheet, which ticks every second only while a command runs; finished ones show a fixed length.
                    let isAnyRunning = model.shownBackgroundCommands.contains { $0.commandState == "running" }
                    TimelineView(.periodic(from: .now, by: isAnyRunning ? 1 : 3_600)) { context in
                        List {
                            ForEach(model.shownBackgroundCommands) { command in
                                BackgroundCommandRow(
                                    command: command, now: context.date, canStop: BackgroundCommandRules.canStop(command, currentUserId: currentUserId),
                                    onStop: { Task { await model.stopBackgroundCommand(command) } })
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Background commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refreshBackgroundCommands() }
        }
    }
}

/// BackgroundCommandRow is one command: the command itself on one line, a small state chip, how long it ran, and the newest of its
/// output in a bordered block that starts at the newest lines and opens to more.
private struct BackgroundCommandRow: View {
    let command: BackgroundCommand
    /// The sheet's clock, for how long a running command has run.
    let now: Date
    let canStop: Bool
    let onStop: () -> Void
    @State private var isExpanded = false
    @ScaledMetric(relativeTo: .caption) private var foldedHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(command.command ?? "")
                .font(.subheadline.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                stateChip
                Text(verbatim: command.elapsed(now: now).map(BackgroundCommandRules.clock) ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if canStop {
                    Button("Stop", role: .destructive, action: onStop)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("backgroundCommandStop")
                }
            }
            output
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backgroundCommandRow")
    }

    private var stateChip: some View {
        Text(stateText)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(stateColor)
            .background(stateColor.opacity(0.14), in: Capsule())
    }

    private var stateText: String {
        switch command.commandState {
        case "running": String(localized: "Running")
        case "exited": command.exitCode.map { String(localized: "Exited \($0)") } ?? String(localized: "Exited")
        case "stopped": String(localized: "Stopped")
        case "timed_out": String(localized: "Timed out")
        case "lost": String(localized: "Lost")
        default: command.commandState ?? ""
        }
    }

    private var stateColor: Color {
        switch command.commandState {
        case "running": Color.accentColor
        case "exited": command.exitCode == 0 ? Color.statusSuccess : Color.statusError
        case "timed_out", "lost": Color.statusError
        default: Color.secondary
        }
    }

    @ViewBuilder
    private var output: some View {
        let text = command.outputTail
        if text.isEmpty {
            Text("No output yet").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // The newest lines show first: the block starts at its end and scrolls up to older ones.
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottomLeading)
                .frame(maxHeight: isExpanded ? foldedHeight * 4 : foldedHeight)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.gray.opacity(0.28), lineWidth: 1))
                .accessibilityIdentifier("backgroundCommandOutput")
                Button(isExpanded ? "Show less" : "Show more") {
                    withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
    }
}
