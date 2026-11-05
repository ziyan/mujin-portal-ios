import Foundation

/// AppUpdateChannel is where this copy of the app came from, which decides where a newer one is found. A build run from
/// Xcode has no channel, and is never told about an update.
public enum AppUpdateChannel: String, Sendable {
    case testFlight
    case appStore
}

/// InstalledApp is the version and build of the running app.
public struct InstalledApp: Equatable, Sendable {
    public let version: String
    public let build: Int

    public init(version: String, build: Int) {
        self.version = version
        self.build = build
    }

    /// Reads the bundle's Info.plist. Nil when it holds no version or a build that is not a number.
    public init?(infoDictionary: [String: Any]?) {
        guard let version = infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty,
            let buildText = infoDictionary?["CFBundleVersion"] as? String, let build = Int(buildText)
        else { return nil }
        self.init(version: version, build: build)
    }
}

/// AppUpdate is a newer copy of the app the person can install from their channel. The App Store says only a version;
/// TestFlight says a build too, since builds of one version come out often.
public struct AppUpdate: Equatable, Sendable {
    public let channel: AppUpdateChannel
    public let version: String
    public let build: Int?

    public init(channel: AppUpdateChannel, version: String, build: Int? = nil) {
        self.channel = channel
        self.version = version
        self.build = build
    }

    /// The version as the app shows it, such as `1.0 (310)`.
    public var versionText: String {
        build.map { "\(version) (\($0))" } ?? version
    }

    /// Names this update alone, so dismissing it says nothing about the next one.
    public var identifier: String {
        "\(channel.rawValue):\(versionText)"
    }

    public var installUrl: URL {
        switch channel {
        case .testFlight: AppUpdateSource.testFlightInstallUrl
        case .appStore: AppUpdateSource.appStoreInstallUrl
        }
    }
}

/// AppUpdateSource is where each channel says what is newest. TestFlight has no public way to ask, so the build pipeline
/// publishes a small feed once a build can be installed; the App Store answers a public lookup.
public enum AppUpdateSource {
    static let testFlightFeedUrl = URL(string: "https://github.com/ziyan/mujin-portal-ios/releases/download/update-feed/testflight.json")!
    static let testFlightInstallUrl = URL(string: "https://testflight.apple.com/join/THYWsZJ8")!
    static let appStoreInstallUrl = URL(string: "https://apps.apple.com/app/id6829099282")!

    /// The address to read. Nil when the App Store lookup has no bundle identifier to ask about.
    public static func requestUrl(channel: AppUpdateChannel, bundleIdentifier: String?, region: String?) -> URL? {
        switch channel {
        case .testFlight:
            return testFlightFeedUrl
        case .appStore:
            guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
            var components = URLComponents(string: "https://itunes.apple.com/lookup")
            components?.queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
            // An app is listed per store: the lookup answers for the United States unless told otherwise.
            if let region, !region.isEmpty { components?.queryItems?.append(URLQueryItem(name: "country", value: region)) }
            return components?.url
        }
    }

    /// The update the channel's answer offers, or nil when the installed app is as new or the answer says nothing usable.
    public static func update(channel: AppUpdateChannel, answer: Data, installed: InstalledApp) -> AppUpdate? {
        switch channel {
        case .testFlight:
            struct Feed: Decodable {
                let version: String
                let build: Int
            }
            guard let feed = try? JSONDecoder().decode(Feed.self, from: answer), feed.build > installed.build else { return nil }
            return AppUpdate(channel: .testFlight, version: feed.version, build: feed.build)
        case .appStore:
            struct Lookup: Decodable {
                struct Listing: Decodable { let version: String }
                let results: [Listing]
            }
            guard let listing = (try? JSONDecoder().decode(Lookup.self, from: answer))?.results.first,
                isVersion(listing.version, newerThan: installed.version)
            else { return nil }
            return AppUpdate(channel: .appStore, version: listing.version)
        }
    }

    /// Compares dotted versions part by part, so 1.10 is newer than 1.9 and 1.0 is the same as 1.0.0.
    static func isVersion(_ version: String, newerThan other: String) -> Bool {
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        let otherParts = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(parts.count, otherParts.count) {
            let part = index < parts.count ? parts[index] : 0
            let otherPart = index < otherParts.count ? otherParts[index] : 0
            if part != otherPart { return part > otherPart }
        }
        return false
    }
}

/// AppUpdateDismissal remembers the one update the person dismissed. A newer update has another identifier, so it shows.
public enum AppUpdateDismissal {
    static let key = "dismissedAppUpdate"

    public static func isDismissed(_ update: AppUpdate, in defaults: UserDefaults = AppGroup.defaults) -> Bool {
        defaults.string(forKey: key) == update.identifier
    }

    public static func dismiss(_ update: AppUpdate, in defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(update.identifier, forKey: key)
    }
}
