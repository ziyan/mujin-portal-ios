import PortalKit
import SwiftUI

/// ChatsView is the place for conversations with colleagues. Portal's chat
/// operations are not in the server yet, so until a server offers them the
/// tab says so instead of showing a list that cannot fill.
struct ChatsView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if session.capabilities.offersChats {
                    ContentUnavailableView {
                        Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start a chat with a colleague from the web app.")
                    }
                } else {
                    List {
                        Section {
                            Label("Chats with colleagues arrive with a Portal update.", systemImage: "clock")
                                .foregroundStyle(.secondary)
                        }
                        Section("Meanwhile") {
                            Label("Ask your assistant", systemImage: "sparkles")
                                .foregroundStyle(.primary)
                            Label("Open a ticket", systemImage: "tray.full")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
        }
    }
}
