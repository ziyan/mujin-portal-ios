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

/// DemoSafariPage stands in for the system's Safari view in the demo, which runs in another process where a UI test cannot see
/// it. It shows the address that was opened and a Done button.
struct DemoSafariPage: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            Text(url.absoluteString)
                .accessibilityIdentifier("safariPageAddress")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("safariPageDone")
                    }
                }
        }
    }
}
