import PortalKit
import SwiftUI

/// MoreView is the last tab: the account, and what does not need a tab of its own.
struct MoreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionModel.self) private var session
    let account: Account

    @State private var isShowingAccounts = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isShowingAccounts = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName).foregroundStyle(.primary)
                            Text(account.server.displayHost).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("accountsButton")
                }
            }
            .navigationTitle("More")
            .sheet(isPresented: $isShowingAccounts) {
                AccountsView()
            }
        }
    }
}
