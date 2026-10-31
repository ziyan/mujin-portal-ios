import PortalKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let account = model.activeAccount {
                ConversationListView(account: account)
                    .id(account.accountKey)
            } else {
                SignInView(isAddingAccount: false)
            }
        }
        .alert(
            "Signed out", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(model.notice ?? "") })
    }
}
