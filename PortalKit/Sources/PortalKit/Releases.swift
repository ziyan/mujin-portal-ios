import Foundation

/// LocalizedString is one language's text of a release description or changelog.
public struct LocalizedString: Codable, Equatable, Hashable, Sendable {
    public let locale: String?
    public let text: String?

    public init(locale: String?, text: String?) {
        self.locale = locale
        self.text = text
    }
}

/// LocalizedTexts picks the text in the person's language from the list a release carries.
public enum LocalizedTexts {
    /// The text for the first preferred language that has one: an exact match (`ja-JP`), then the same
    /// language (`ja`), with Chinese told apart by script or region; then English; then any text at all.
    public static func pick(_ texts: [LocalizedString]?, preferredLanguages: [String]) -> String? {
        let usable = (texts ?? []).filter { !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return nil }
        func normalized(_ identifier: String) -> String { identifier.lowercased().replacingOccurrences(of: "_", with: "-") }
        func chinese(_ identifier: String) -> String? {
            let parts = normalized(identifier)
            guard parts.hasPrefix("zh") else { return nil }
            return (parts.contains("hant") || parts.hasSuffix("-tw") || parts.hasSuffix("-hk") || parts.hasSuffix("-mo")) ? "zh-tw" : "zh-cn"
        }
        for preferred in preferredLanguages {
            let wanted = chinese(preferred) ?? normalized(preferred)
            if let exact = usable.first(where: { normalized($0.locale ?? "") == wanted }) { return exact.text }
            let language = wanted.split(separator: "-").first.map(String.init) ?? wanted
            if let same = usable.first(where: { (normalized($0.locale ?? "").split(separator: "-").first.map(String.init) ?? "") == language }), language != "zh" {
                return same.text
            }
        }
        if let english = usable.first(where: { normalized($0.locale ?? "") == "en" || normalized($0.locale ?? "").hasPrefix("en-") }) { return english.text }
        return usable.first?.text
    }
}

/// Release is one release of the controller software, as the release catalog lists it.
public struct Release: Codable, Equatable, Hashable, Identifiable, Sendable {
    public struct Image: Codable, Equatable, Hashable, Identifiable, Sendable {
        public let id: String
        public let tag: String?
        public let labelVersion: String?
        public let labelPreset: String?
        public let labelProject: String?
    }

    public let id: String
    public let name: String?
    public let application: String?
    public let channel: String?
    /// `draft`, `published` or `withdrawn`.
    public let status: String?
    public let versionString: String?
    public let createdAt: String?
    public let deletedAt: String?
    public let description: [LocalizedString]?
    public let changelog: [LocalizedString]?
    public let images: [Image]?

    public init(
        id: String, name: String? = nil, application: String? = nil, channel: String? = nil, status: String? = "published", versionString: String? = nil,
        createdAt: String? = nil, description: [LocalizedString]? = nil, changelog: [LocalizedString]? = nil, images: [Image]? = nil, deletedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.application = application
        self.channel = channel
        self.status = status
        self.versionString = versionString
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.description = description
        self.changelog = changelog
        self.images = images
    }

    /// What a chip or a row calls it: the name, else the version, else the id.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let versionString, !versionString.isEmpty { return versionString }
        return id
    }

    public var date: Date? { PortalDate.parse(createdAt) }

    public func descriptionText(preferredLanguages: [String]) -> String? { LocalizedTexts.pick(description, preferredLanguages: preferredLanguages) }
    public func changelogText(preferredLanguages: [String]) -> String? { LocalizedTexts.pick(changelog, preferredLanguages: preferredLanguages) }

    /// The numbers of a version, such as 0.49.0 as [0, 49, 0]. Text without numbers has none.
    static func versionNumbers(_ version: String?) -> [Int] {
        (version ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// Newest day first; within one day the higher version first (0.49.0 above 0.45.4), then the later time.
    public static func newestFirst(_ releases: [Release]) -> [Release] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func day(_ release: Release) -> Date { calendar.startOfDay(for: release.date ?? .distantPast) }
        return releases.filter { $0.deletedAt == nil }.sorted { first, second in
            if day(first) != day(second) { return day(first) > day(second) }
            let firstNumbers = versionNumbers(first.versionString)
            let secondNumbers = versionNumbers(second.versionString)
            if firstNumbers != secondNumbers { return firstNumbers.lexicographicallyPrecedes(secondNumbers) == false }
            return (first.date ?? .distantPast) > (second.date ?? .distantPast)
        }
    }
}

/// ControllerRelease says how a controller lines up with the release catalog, as the web's release chip does.
public enum ControllerRelease: Equatable, Sendable {
    /// Neither id is set: a development build, a version no release matches, or nothing reported yet.
    case notLinked
    /// The release matches by version only: no registered image matches its labels.
    case versionOnly(releaseId: String)
    case exact(releaseId: String)

    public init(releaseId: String?, releaseImageId: String?) {
        guard let releaseId, !releaseId.isEmpty else {
            self = .notLinked
            return
        }
        self = (releaseImageId ?? "").isEmpty ? .versionOnly(releaseId: releaseId) : .exact(releaseId: releaseId)
    }

    public var releaseId: String? {
        switch self {
        case .notLinked: nil
        case .versionOnly(let id), .exact(let id): id
        }
    }
}

/// BrowserTarget says what the built-in browser is showing before the page has a title: which machine and which of its
/// web UIs, so the live and the cloud one can be told apart.
public struct BrowserTarget: Equatable, Sendable {
    public let title: String
    public let subtitle: String

    /// `controller01 · Live` for `<id>-live.<host>`, `· Cloud`, `· Virtual`; nil for any other address.
    public init?(url: URL, serverHost: String) {
        guard let host = url.host?.lowercased(), ControllerLinks.isControllerHost(host, serverHost: serverHost) else { return nil }
        let label = String(host.dropLast(serverHost.count + 1))
        guard let dash = label.lastIndex(of: "-") else { return nil }
        let kind = label[label.index(after: dash)...]
        let name: String
        switch kind {
        case "live": name = "Live"
        case "cloud": name = "Cloud"
        case "virtual": name = "Virtual"
        default: return nil
        }
        title = "\(label[..<dash]) \u{00B7} \(name)"
        subtitle = host
    }
}

extension Documents {
    static let releaseFields = """
        id name application channel status versionString createdAt deletedAt description { locale text } changelog { locale text }
        images { id tag labelVersion labelPreset labelProject }
        """

    public static let listReleases = """
        query ListReleases($application: String, $channel: String, $includeDeleted: Boolean, $options: ListOptionsInput) {
          ListReleases(application: $application, channel: $channel, includeDeleted: $includeDeleted, options: $options) {
            releases { \(releaseFields) }
            meta { totalCount }
          }
        }
        """

    public static let getRelease = """
        query GetRelease($releaseId: String) { GetRelease(releaseId: $releaseId) { \(releaseFields) } }
        """

    public static let listControllersUsingRelease = """
        query ListControllersUsingRelease($releaseId: String) {
          ListControllersUsingRelease(releaseId: $releaseId) { id siteId comment releaseId releaseImageId }
        }
        """

    public static let listVirtualControllersUsingRelease = """
        query ListVirtualControllersUsingRelease($releaseId: String) {
          ListVirtualControllersUsingRelease(releaseId: $releaseId) { id siteId name status releaseId releaseImageId }
        }
        """

    static var releaseDocuments: [String] { [listReleases, getRelease, listControllersUsingRelease, listVirtualControllersUsingRelease] }
}

extension Connection {
    /// The releases the person may see, newest first. A custom channel's releases come only where the server returns them.
    public func releases(first: Int = 100) async throws -> [Release] {
        struct Answer: Decodable, Sendable {
            struct List: Decodable, Sendable { let releases: [Release]? }
            let ListReleases: List?
        }
        let rows = try await execute(Documents.listReleases, variables: ["options": .object(["first": .number(Double(first))])], as: Answer.self).ListReleases?.releases ?? []
        return Release.newestFirst(rows)
    }

    public func release(id: String) async throws -> Release {
        struct Answer: Decodable, Sendable { let GetRelease: Release }
        return try await execute(Documents.getRelease, variables: ["releaseId": .string(id)], as: Answer.self).GetRelease
    }

    public func controllers(usingRelease id: String) async throws -> [ControllerSummary] {
        struct Answer: Decodable, Sendable { let ListControllersUsingRelease: [ControllerSummary]? }
        return try await execute(Documents.listControllersUsingRelease, variables: ["releaseId": .string(id)], as: Answer.self).ListControllersUsingRelease ?? []
    }

    public func virtualControllers(usingRelease id: String) async throws -> [VirtualControllerSummary] {
        struct Answer: Decodable, Sendable { let ListVirtualControllersUsingRelease: [VirtualControllerSummary]? }
        return try await execute(Documents.listVirtualControllersUsingRelease, variables: ["releaseId": .string(id)], as: Answer.self).ListVirtualControllersUsingRelease ?? []
    }
}
