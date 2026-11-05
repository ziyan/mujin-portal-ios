import PortalKit
import SwiftUI
import UIKit

/// AppUpdateModel finds out whether the person's channel offers a newer app. A failed check shows nothing and is tried again
/// the next time the app comes to the front.
@MainActor
@Observable
final class AppUpdateModel {
    /// The newest update on offer, put off or not: Settings keeps offering it.
    private(set) var update: AppUpdate?
    private(set) var isDismissed = false

    private var lastCheckedAt: Date?
    private var isChecking = false

    /// How long an answer stands. New builds come out at most a few times a day.
    private static let checkIntervalSeconds: TimeInterval = 6 * 60 * 60

    init() {
        if let demo = DemoOptions.update { show(demo) }
    }

    /// The update for the card in Chat: gone once put off, until a newer one arrives.
    var updateForCard: AppUpdate? { isDismissed ? nil : update }

    func checkIfDue() async {
        guard DemoOptions.update == nil, !isChecking else { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkIntervalSeconds { return }
        isChecking = true
        defer { isChecking = false }
        guard let channel = Self.detectChannel(), let installed = InstalledApp(infoDictionary: Bundle.main.infoDictionary),
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

    /// Which store this copy came from. A simulator has no store, whatever its receipt path says.
    private static func detectChannel() -> AppUpdateChannel? {
        #if targetEnvironment(simulator)
            return nil
        #else
            return AppUpdateChannel(
                hasProvisioningProfile: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil,
                receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
        #endif
    }
}

extension AppUpdate {
    /// Names the place the button goes.
    var openTitle: LocalizedStringKey {
        switch channel {
        case .testFlight: "Open TestFlight"
        case .appStore: "Open the App Store"
        }
    }

    /// Says what the update is and where it comes from.
    var sourceText: LocalizedStringKey {
        switch channel {
        case .testFlight: "\(versionText) is ready in TestFlight"
        case .appStore: "\(versionText) is ready on the App Store"
        }
    }
}

/// AppUpdateCard sits at the top of the chat list and tells the person a newer app can be installed. "Not now" puts off this
/// update alone; Settings keeps offering it.
struct AppUpdateCard: View {
    let update: AppUpdate
    let onOpen: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available").font(.headline)
                    Text(update.sourceText).font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("appUpdateCard")
            }
            // Side by side while they fit, one above the other at the largest text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: onOpen) { Text(update.openTitle).lineLimit(1) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("appUpdateOpen")
        Button(action: onNotNow) { Text("Not now").lineLimit(1) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("appUpdateNotNow")
    }
}
