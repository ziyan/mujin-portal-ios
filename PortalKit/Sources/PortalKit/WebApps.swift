import Foundation

/// ControllerWebApp is one web app installed on a controller or a virtual controller, as the controller page lists it.
public struct ControllerWebApp: Decodable, Equatable, Hashable, Identifiable, Sendable {
    public let webAppId: String
    public let name: String?
    public let versionString: String?
    /// The page that shows the app, such as `/app/<route>`, under the controller's web UI host.
    public let openPath: String?
    /// A path on the Portal host that serves the app's icon to the account's token, or nil when the app has none.
    public let iconUrl: String?

    public var id: String { webAppId }

    public init(webAppId: String, name: String? = nil, versionString: String? = nil, openPath: String? = nil, iconUrl: String? = nil) {
        self.webAppId = webAppId
        self.name = name
        self.versionString = versionString
        self.openPath = openPath
        self.iconUrl = iconUrl
    }

    public var displayName: String {
        let text = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? webAppId : text
    }

    /// The icon as a picture the account's store can fetch, or nil when the app has no icon or the path is not one of Portal's.
    public var iconSubject: AvatarSubject? {
        guard let iconUrl, iconUrl.hasPrefix("/api/v1/"), !iconUrl.contains(".."), !iconUrl.contains("?") else { return nil }
        return AvatarSubject(kind: .picture, id: iconUrl, modifiedAt: versionString)
    }
}

/// ControllerWebAppList is what the server answers for a controller's apps.
public struct ControllerWebAppList: Equatable, Sendable {
    /// False when no web UI could be reached to ask: the controller is offline with no synced copy, or the virtual controller is not running.
    public let isAvailable: Bool
    /// `live`, `cloud` or `virtual`: which of the controller's web UIs the apps open in.
    public let source: String?
    public let webApps: [ControllerWebApp]

    public init(isAvailable: Bool, source: String? = nil, webApps: [ControllerWebApp] = []) {
        self.isAvailable = isAvailable
        self.source = source
        self.webApps = webApps
    }
}

extension ControllerLinks {
    /// The address of an app's page: the server's `openPath` on the host of the web UI the list came from. Nil for a path that is
    /// not an app page of that host, so a server cannot send the browser anywhere else.
    public static func appURL(controllerId: String, source: String?, openPath: String, server: ServerAddress) -> URL? {
        let base = source == "cloud" ? cloudURL(controllerId: controllerId, server: server) : liveURL(controllerId: controllerId, server: server)
        return appURL(base: base, openPath: openPath)
    }

    public static func virtualAppURL(virtualControllerId: String, openPath: String, server: ServerAddress) -> URL? {
        appURL(base: virtualURL(virtualControllerId: virtualControllerId, server: server), openPath: openPath)
    }

    private static func appURL(base: URL?, openPath: String) -> URL? {
        guard let base, openPath.hasPrefix("/app/"), openPath.count <= 300,
            !openPath.contains("?"), !openPath.contains("#"), !openPath.contains("\\"), !openPath.contains("//"),
            !openPath.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }),
            !openPath.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.percentEncodedPath = openPath
        return components.url
    }
}

extension ServerCapabilities {
    /// A controller's installed web apps, listed with their icons.
    public var offersControllerWebApps: Bool { offersQuery("ListControllerWebApps") }
}

extension Documents {
    public static let listControllerWebApps = """
        query ListControllerWebApps($controllerId: String, $virtualControllerId: String) {
          ListControllerWebApps(controllerId: $controllerId, virtualControllerId: $virtualControllerId) {
            isAvailable source
            webApps { webAppId name versionString openPath iconUrl }
          }
        }
        """

    static var webAppDocuments: [String] { [listControllerWebApps] }
}

extension Connection {
    /// The web apps of a controller, or of a virtual controller when only its id is given.
    public func controllerWebApps(controllerId: String? = nil, virtualControllerId: String? = nil) async throws -> ControllerWebAppList {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable {
                let isAvailable: Bool?
                let source: String?
                let webApps: [Lossy<ControllerWebApp>?]?
            }
            let ListControllerWebApps: List?
        }
        var variables: [String: JSONValue] = [:]
        if let controllerId { variables["controllerId"] = .string(controllerId) }
        if let virtualControllerId { variables["virtualControllerId"] = .string(virtualControllerId) }
        let list = try await execute(Documents.listControllerWebApps, variables: variables, as: Answer.self).ListControllerWebApps
        guard let list, list.isAvailable == true else { return ControllerWebAppList(isAvailable: false) }
        let apps = (list.webApps ?? []).compactMap { $0?.value }.filter { !($0.openPath ?? "").isEmpty }
        return ControllerWebAppList(isAvailable: true, source: list.source, webApps: apps)
    }
}

extension ControllerEntry {
    /// Whether the entry has a page to open.
    public var isOpen: Bool {
        if case .open = self { return true }
        return false
    }
}
