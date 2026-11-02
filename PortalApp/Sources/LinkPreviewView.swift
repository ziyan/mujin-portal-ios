import PortalKit
import SwiftUI
import UIKit

/// LinkPreviewCardView is the card under a message that holds a link. A
/// Portal link opens in the app, an outside one in the browser. The picture
/// comes from Portal's own copy, never from the outside address.
struct LinkPreviewCardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    @Environment(\.openURL) private var openURL
    let card: LinkPreviewCard
    let connection: Connection

    @State private var imageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 140)
                    .clipped()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(labelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let title = card.title, !title.isEmpty {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                }
                if card.isExternal, let description = card.description, !description.isEmpty {
                    Text(description).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                if !card.isExternal, let status = card.statusText, !status.isEmpty {
                    Text(card.linkKind == "ticket" ? TicketText.status(status) : status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .contextMenu {
            Button(action: open) { Label("Open", systemImage: "arrow.up.right.square") }
            if let address = card.url, let url = URL(string: address) {
                ShareLink(item: url)
            }
        }
        .task {
            // The demo run taps the ticket card once it has shown, as a person does.
            guard appModel.isDemo, DemoOptions.screen == "chat-link-tap", card.linkKind == "ticket" else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { open() }
        }
        .task(id: card.urlHash) {
            guard !appModel.isDemo, let path = card.imageUrl, path.hasPrefix("/api/") else { return }
            imageData = try? await connection.fetch(path: path)
        }
    }

    /// labelText is the small line above the title: the site an outside page
    /// came from, or for a Portal link what it is ("Ticket #12"), the same as
    /// the web card.
    private var labelText: String {
        if card.isExternal { return card.siteName ?? hostText }
        return card.description ?? ""
    }

    private var hostText: String {
        URL(string: card.url ?? "")?.host ?? ""
    }

    private func open() {
        if card.isExternal {
            if let address = card.url, let url = URL(string: address) { openURL(url) }
        } else if let path = card.path, !path.isEmpty {
            openURL(session.account.server.endpoint(path))
        }
    }
}
