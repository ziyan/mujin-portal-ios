import PortalKit
import SwiftUI

/// SignInView signs in to a Portal instance: the default one with a single
/// button, or any other whose https address the person types.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let isAddingAccount: Bool

    @State private var isUsingOtherServer = false
    @State private var serverText = ""
    @State private var addressError: String?
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .padding(.top, 48)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("Portal")
                            .font(.largeTitle.bold())
                        Text("Ask your assistant, answer its questions and approve what it wants to do.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(spacing: 12) {
                        if !isUsingOtherServer {
                            Button {
                                Task { await model.signIn(to: .production) }
                            } label: {
                                Text("Sign in to \(ServerAddress.production.displayHost)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.isSigningIn)
                            Button("Use another server") {
                                isUsingOtherServer = true
                                isAddressFocused = true
                            }
                            .disabled(model.isSigningIn)
                        } else {
                            TextField("https://portal.example.com", text: $serverText)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isAddressFocused)
                                .submitLabel(.go)
                                .onSubmit(continueWithOtherServer)
                            Button {
                                continueWithOtherServer()
                            } label: {
                                Text("Continue")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.isSigningIn || serverText.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Use \(ServerAddress.production.displayHost)") {
                                isUsingOtherServer = false
                                addressError = nil
                            }
                            .disabled(model.isSigningIn)
                        }
                        if model.isSigningIn {
                            ProgressView()
                        }
                        if let message = addressError ?? model.signInError {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("signInError")
                        }
                    }
                    .frame(maxWidth: 420)
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .toolbar {
                if isAddingAccount {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: model.accounts.count) { _, _ in
            if isAddingAccount { dismiss() }
        }
    }

    private func continueWithOtherServer() {
        do {
            let server = try ServerAddress(serverText)
            addressError = nil
            Task { await model.signIn(to: server) }
        } catch {
            addressError = error.userMessage
        }
    }
}

#Preview("Sign in") {
    SignInView(isAddingAccount: false)
        .environment(DemoServer.makeModel(isSignedIn: false))
}
