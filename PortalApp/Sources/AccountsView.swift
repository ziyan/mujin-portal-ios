import PortalKit
import SwiftUI

/// AccountsView lists the accounts on this phone, switches between them,
/// adds one and signs out of one.
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var accountToRemove: Account?

    var body: some View {
        NavigationStack {
            List { PortalRows {
                Section {
                    ForEach(model.accounts, id: \.accountKey) { account in
                        Button {
                            model.switchTo(account)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: account.accountKey == model.activeAccount?.accountKey ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(account.accountKey == model.activeAccount?.accountKey ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .foregroundStyle(.primary)
                                    Text(account.server.displayHost)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityAddTraits(account.accountKey == model.activeAccount?.accountKey ? .isSelected : [])
                        .swipeActions {
                            Button("Sign out", role: .destructive) { accountToRemove = account }
                        }
                    }
                }
                Section {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add account", systemImage: "plus.circle")
                    }
                }
            } }
.portalList()
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAdding) {
                SignInView(isAddingAccount: true)
            }
            .confirmationDialog(
                "Sign out of this account?", isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } }),
                titleVisibility: .visible, presenting: accountToRemove
            ) { account in
                Button("Sign out of \(account.displayName)", role: .destructive) {
                    Task { await model.remove(account) }
                }
            } message: { account in
                Text("\(account.displayName) on \(account.server.displayHost) will be removed from this phone.")
            }
        }
        .frame(minWidth: 340, minHeight: 380)
        .presentationDetents([.medium, .large])
    }
}

#Preview("Accounts") {
    AccountsView()
        .environment(DemoServer.makeModel())
}
