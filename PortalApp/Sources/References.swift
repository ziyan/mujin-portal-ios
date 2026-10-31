import PortalKit
import SwiftUI

/// ReplyCard is the message a reply is about, shown above the composer with
/// a bar in the accent color and a button that takes it away. The quoted
/// words are never put in the text field.
struct ReplyCard: View {
    let reply: ReplyReference
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.footnote)
                .foregroundStyle(Color.portalSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if reply.isOwn {
                        Text("Replying to yourself")
                    } else {
                        Text("Replying to \(reply.authorName)")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                Text(reply.excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RemoveButton(label: Text("Cancel reply"), action: onCancel)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.accentColor).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// ReferenceChip is another thing a message refers to: the page or resource
/// being asked about, or a file attached to it. It has a button that takes
/// it away.
struct ReferenceChip: View {
    let systemImage: String
    let text: String
    var detail: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.portalSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            RemoveButton(label: Text("Remove \(text)"), action: onRemove)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

/// RemoveButton is the small x on a reply card or a chip. It is at least 44
/// points to tap, though it draws small.
private struct RemoveButton: View {
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.portalSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// ReferencesBar is the area between the transcript and the composer: at
/// most one reply card, then the chips. Nothing in it is part of the text.
struct ReferencesBar<Chips: View>: View {
    let reply: ReplyReference?
    let onCancelReply: () -> Void
    @ViewBuilder let chips: Chips

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply {
                ReplyCard(reply: reply, onCancel: onCancelReply)
            }
            chips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// SentQuote is the compact quote above a sent reply, which is what the
/// reply card became.
struct SentQuote: View {
    let authorName: String
    let excerpt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !authorName.isEmpty {
                Text(authorName).font(.caption.weight(.semibold))
            }
            Text(excerpt).font(.caption).lineLimit(2)
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: 2) }
        .accessibilityElement(children: .combine)
    }
}
