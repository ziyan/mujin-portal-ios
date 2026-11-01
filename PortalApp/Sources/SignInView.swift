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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let palette = WelcomePalette.palette(for: colorScheme)
        NavigationStack {
            ZStack {
                WelcomeBackdrop()
                // The schematic arm sits low and to the left, behind the type. On a wide screen it grows to a third of the height.
                GeometryReader { proxy in
                    let scale = horizontalSizeClass == .regular ? proxy.size.height * 0.34 / 460 : min(1, proxy.size.width / 420) * 0.95
                    WelcomeArm()
                        .frame(width: 360, height: 460)
                        .scaleEffect(scale, anchor: .bottomLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 8)
                        .padding(.bottom, 24)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Image("MujinLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 30)
                                .accessibilityHidden(true)
                            Spacer()
                        }
                        .padding(.top, 12)
                        Spacer(minLength: 56)
                        VStack(spacing: 0) {
                        VStack(spacing: 14) {
                            Text("Welcome to")
                                .font(.caption.weight(.medium))
                                .tracking(6)
                                .textCase(.uppercase)
                                .foregroundStyle(WelcomePalette.orange)
                            Text("Mujin Portal")
                                .font(.system(size: 56, weight: .ultraLight))
                                .tracking(2)
                                .minimumScaleFactor(0.6)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 4)
                                .foregroundStyle(LinearGradient(colors: palette.wordmark, startPoint: .top, endPoint: .bottom))
                                .accessibilityAddTraits(.isHeader)
                            Text("Manage your Mujin controllers from anywhere.")
                                .font(.body)
                                .foregroundStyle(palette.textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }
                        Color.clear.frame(height: 40)
                        actions(palette)
                            .frame(maxWidth: 420)
                        }
                        // On a wide screen the group sits a little above the middle; on a phone it keeps its place near the top.
                        .padding(.bottom, horizontalSizeClass == .regular ? 96 : 24)
                        if horizontalSizeClass == .regular { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: horizontalSizeClass == .regular ? viewport.size.height : 0)
                }
                .scrollBounceBehavior(.basedOnSize)
                }
            }
            .toolbar {
                if isAddingAccount {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        // Everything follows the text size together, up to a limit that keeps the link smaller than the button and off the drawing.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onChange(of: model.accounts.count) { _, _ in
            if isAddingAccount { dismiss() }
        }
    }

    @ViewBuilder
    private func actions(_ palette: WelcomePalette) -> some View {
        VStack(spacing: 14) {
            if !isUsingOtherServer {
                Button {
                    Task { await model.signIn(to: .production) }
                } label: {
                    Text("Sign in to \(ServerAddress.production.displayHost)")
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .foregroundStyle(palette.ctaText)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(LinearGradient(colors: palette.ctaFill, startPoint: .top, endPoint: .bottom), in: Capsule())
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [WelcomePalette.orange, WelcomePalette.amber], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isSigningIn)
                Button("Use another server") {
                    isUsingOtherServer = true
                    isAddressFocused = true
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textMuted)
                .disabled(model.isSigningIn)
            } else {
                TextField("https://portal.example.com", text: $serverText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(.thinMaterial, in: Capsule())
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
                        .font(.headline)
                        .foregroundStyle(palette.ctaText)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(LinearGradient(colors: palette.ctaFill, startPoint: .top, endPoint: .bottom), in: Capsule())
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [WelcomePalette.orange, WelcomePalette.amber], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isSigningIn || serverText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Use \(ServerAddress.production.displayHost)") {
                    isUsingOtherServer = false
                    addressError = nil
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textMuted)
                .disabled(model.isSigningIn)
            }
            if model.isSigningIn {
                ProgressView()
            }
            if let message = addressError ?? model.signInError {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.statusError)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("signInError")
            }
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
