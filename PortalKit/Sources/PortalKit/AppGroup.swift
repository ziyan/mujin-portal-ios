import Foundation

/// AppGroup is the folder and the settings the app shares with its extensions.
public enum AppGroup {
    /// The group's identifier, which the build puts in each Info.plist.
    public static var identifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "PortalAppGroup") as? String
        return value?.isEmpty == false ? value : nil
    }

    public static var containerURL: URL? {
        #if canImport(Darwin)
            return identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        #else
            return nil
        #endif
    }

    /// Where shared files are kept: the group's folder, or a temporary one
    /// where there is no group (a build that is not signed, the demo).
    public static func shareJobStore() -> FileShareJobStore {
        let base = containerURL ?? FileManager.default.temporaryDirectory
        return FileShareJobStore(root: base.appendingPathComponent("share-jobs", isDirectory: true))
    }

    public static var defaults: UserDefaults {
        identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
}

/// PushDeviceToken is the token Apple gave this phone for push notifications,
/// kept in the app group until the server has a place to register it.
public enum PushDeviceToken {
    static let key = "pushDeviceToken"

    /// The token as the hexadecimal text servers expect.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    public static func store(_ token: Data, in defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(hex(token), forKey: key)
    }

    public static func stored(in defaults: UserDefaults = AppGroup.defaults) -> String? {
        defaults.string(forKey: key)
    }
}
