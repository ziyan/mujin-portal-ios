import PortalKit
import SwiftUI

/// AskAboutButton starts a conversation about the screen it is on. The
/// conversation opens with the resource shown as a reference above the
/// composer, which the person can take away; they type their question there.
struct AskAboutButton: View {
    @Environment(SessionModel.self) private var session
    let viewing: Viewing
    let subject: String

    var body: some View {
        Button {
            Task { await session.beginAsk(about: viewing, subject: subject) }
        } label: {
            Label("Ask about this", systemImage: "sparkles")
        }
    }
}
