import PortalKit
import StoreKit
import SwiftUI
import UIKit

/// AppUpdateModel finds out whether the person's channel offers a newer app. A failed check shows nothing and is tried again
/// the next time the app comes to the front.
@MainActor
@Observable
final class AppUpdateModel {
    /// The newest update on offer, dismissed or not: About keeps offering it.
    private(set) var update: AppUpdate?
    private(set) var isDismissed = false

    private var lastCheckedAt: Date?
    private var isChecking = false

    /// How long an answer stands. New builds come out at most a few times a day.
    private static let checkIntervalSeconds: TimeInterval = 6 * 60 * 60

    init() {
        if let demo = DemoOptions.update { show(demo) }
    }

    /// The update for the bar: gone once dismissed, until a newer one arrives.
    var updateForBar: AppUpdate? { isDismissed ? nil : update }

    func checkIfDue() async {
        guard DemoOptions.update == nil, !isChecking else { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkIntervalSeconds { return }
        isChecking = true
        defer { isChecking = false }
        guard let channel = await Self.detectChannel(), let installed = InstalledApp(infoDictionary: Bundle.main.infoDictionary),
            let address = AppUpdateSource.requestUrl(
                channel: channel, bundleIdentifier: Bundle.main.bundleIdentifier, region: Locale.current.region?.identifier)
        else { return }
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        guard let (answer, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return }
        lastCheckedAt = Date()
        show(AppUpdateSource.update(channel: channel, answer: answer, installed: installed))
    }

    func dismiss() {
        guard let update else { return }
        AppUpdateDismissal.dismiss(update)
        isDismissed = true
    }

    /// Goes to TestFlight or the App Store, never the built-in browser.
    func install() {
        guard let update else { return }
        UIApplication.shared.open(update.installUrl)
    }

    private func show(_ newest: AppUpdate?) {
        update = newest
        isDismissed = newest.map { AppUpdateDismissal.isDismissed($0) } ?? false
    }

    /// TestFlight builds run in the sandbox environment, App Store copies in production, and a build from Xcode in neither.
    private static func detectChannel() async -> AppUpdateChannel? {
        guard let transaction = try? await AppTransaction.shared else { return nil }
        switch transaction.unsafePayloadValue.environment {
        case .production: return .appStore
        case .sandbox: return .testFlight
        default: return nil
        }
    }
}

extension AppUpdate {
    /// Says what the update is and where it comes from.
    var sourceText: LocalizedStringKey {
        switch channel {
        case .testFlight: "\(versionText) is ready in TestFlight"
        case .appStore: "\(versionText) is ready on the App Store"
        }
    }
}

/// AppUpdateBar tells the person a newer app can be installed. It sits above the content and pushes it down, so it never covers
/// a composer, and closing it dismisses this update.
struct AppUpdateBar: View {
    let update: AppUpdate
    let onInstall: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down")
                .foregroundStyle(Color.onAccent)
                .frame(width: 32, height: 32)
                .background(Color.accentColor, in: .circle)
                .fixedSize()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Update available").font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(update.sourceText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("appUpdateBar")
            Spacer(minLength: 4)
            Button("Update", action: onInstall)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("appUpdateInstall")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("appUpdateDismiss")
        }
        // The bar keeps to one line of controls: its text stops growing at the largest ordinary size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}
