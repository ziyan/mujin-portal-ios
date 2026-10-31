import SafariServices
import SwiftUI

/// IdentifiableURL lets a web address be the item of a presentation.
struct IdentifiableURL: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SafariView is the system's Safari view, for links that leave Portal.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
