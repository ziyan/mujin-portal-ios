import PortalKit
import SwiftUI

/// ThreadReplyControl sits under the root of a thread that has two or more replies and says how many, in plain accent text, or that
/// the assistant is answering there. Tapping it opens the thread alone. It is a full-size tap target.
struct ThreadReplyControl: View {
    let summary: ThreadSummary?
    let isWorking: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text("Working on an answer…").font(.footnote).foregroundStyle(.secondary)
                } else if let summary {
                    Text(ThreadText.replyCount(summary.replyCount)).font(.footnote)
                }
            }
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

/// ThreadCommentLine sits above the first reply of a run in the main history and says which message it comments on. The start of
/// that message is in the accent color and a tap opens the thread. It is one line and never wider than the transcript. With no
/// `author` the message is the person's own.
struct ThreadCommentLine: View {
    let author: String?
    let excerpt: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            (author.map { Text("Commented on \($0)'s message:") } ?? Text("Commented on your message:")) + Text(" ")
                + Text(excerpt).foregroundStyle(Color.accentColor)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint(Text("Open the thread"))
        .accessibilityIdentifier("threadCommentLine")
    }
}

extension View {
    /// The bar beside a message of a thread, always on the left edge of the row. It is solid, and reaches down into the gap to the
    /// next row when that one is part of the same thread, so it runs unbroken.
    @ViewBuilder
    func threadBar(isShown: Bool, joinsBelow: Bool, gap: CGFloat) -> some View {
        if isShown {
            padding(.leading, 10)
                .background(alignment: .leading) {
                    Rectangle().fill(Color.accentColor).frame(width: 2).padding(.bottom, joinsBelow ? -gap : 0)
                }
        } else {
            self
        }
    }
}

enum ThreadExcerpt {
    /// The start of a message on one line.
    static func start(of text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > 80 ? String(line.prefix(79)) + "\u{2026}" : line
    }
}
