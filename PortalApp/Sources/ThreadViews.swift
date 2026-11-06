import PortalKit
import SwiftUI

/// ThreadReplyControl sits under a message that has a thread: how many replies it holds and when the last came, or that the
/// assistant is answering there. Tapping it opens the thread alone. It is a full-size tap target.
struct ThreadReplyControl: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: ThreadSummary?
    let isWorking: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                HStack(spacing: 6) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bubble.left.and.bubble.right").accessibilityHidden(true)
                    }
                    if let summary {
                        Text(ThreadText.replyCount(summary.replyCount)).font(.footnote.weight(.semibold))
                    }
                }
                if isWorking {
                    Text("Working on an answer…").font(.caption).foregroundStyle(.secondary)
                } else if let date = summary?.lastReplyDate {
                    Text(date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityHint(Text("Open the thread"))
        .accessibilityIdentifier("threadReplyControl")
    }
}

/// ThreadRepliesDivider sits under the message a thread hangs from and says how many replies follow.
struct ThreadRepliesDivider: View {
    let replyCount: Int

    var body: some View {
        HStack(spacing: 8) {
            (replyCount == 0 ? Text("No replies yet") : Text(ThreadText.replyCount(replyCount)))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("threadRepliesDivider")
    }
}

enum ThreadText {
    /// "1 reply" or "3 replies".
    static func replyCount(_ count: Int) -> LocalizedStringKey {
        count == 1 ? LocalizedStringKey("1 reply") : LocalizedStringKey("\(count) replies")
    }
}
