import PortalKit
import SwiftUI

/// ReferenceChipRow shows, under a chat message, what it names: a ticket with its number, title and status, a controller with whether
/// it is connected, a virtual controller, a site, a cell with its site. A tap opens the thing's screen. What the reader may not see is
/// left out: it reads only as the words that were written.
struct ReferenceChipRow: View {
    let references: [ChatReference]
    let onOpen: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(references, id: \.self) { reference in
                Button { if let path = reference.path { onOpen(path) } } label: { MessageReferenceChip(reference: reference) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("referenceChip")
            }
        }
    }
}

/// MessageReferenceChip is one thing a message names: its kind's symbol and what it is called, and for a ticket its status.
struct MessageReferenceChip: View {
    let reference: ChatReference

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            Text(reference.chipText).font(.caption.weight(.semibold)).lineLimit(1)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch reference.referenceKind {
        case "ticket": "ticket"
        case "controller": "cpu"
        case "virtual_controller": "cube.transparent"
        case "site": "building.2"
        case "cell": "square.grid.2x2"
        default: "link"
        }
    }

    private var detail: String? {
        switch reference.referenceKind {
        case "ticket": reference.ticketStatus.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        case "controller": reference.isControllerConnected.map { $0 ? String(localized: "Connected") : String(localized: "Not connected") }
        case "cell": reference.cellSiteName
        default: nil
        }
    }
}

/// FlowLayout sets its views in rows, starting a new row when the next one does not fit, as words wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
