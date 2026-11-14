import Foundation

/// ArtifactReference is a page, drawing or document the assistant made with
/// its artifact tool.
public struct ArtifactReference: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case html
        case svg
        case markdown
    }

    public let id: String
    public let title: String
    public let kind: Kind
    public let sizeBytes: Int64?
    /// The thread the artifact was made in, where the list says; nil for the main history or when it does not say.
    public let threadRootMessageId: String?
    /// When it was made, where the list says.
    public let createdAt: String?

    public init(
        id: String, title: String, kind: Kind, sizeBytes: Int64? = nil, threadRootMessageId: String? = nil, createdAt: String? = nil
    ) {
        self.threadRootMessageId = ThreadRouting.normalized(threadRootMessageId)
        self.createdAt = createdAt
        self.id = id
        self.title = title
        self.kind = kind
        self.sizeBytes = sizeBytes
    }
}

/// ProducedFile is a file a shell command wrote to its output folder.
public struct ProducedFile: Equatable, Identifiable, Sendable {
    public let attachmentId: String
    public let name: String
    public let contentType: String
    public let url: String?
    public let sizeBytes: Int64?
    public var id: String { attachmentId }

    public init(attachmentId: String, name: String, contentType: String, url: String? = nil, sizeBytes: Int64? = nil) {
        self.attachmentId = attachmentId
        self.name = name
        self.contentType = contentType
        self.url = url
        self.sizeBytes = sizeBytes
    }

    public var isImage: Bool { contentType.lowercased().hasPrefix("image/") }
}

/// ProducedItem is what a tool call made that the person should see even
/// when tool details are off.
public enum ProducedItem: Equatable, Identifiable, Sendable {
    case artifact(ArtifactReference)
    case file(ProducedFile)

    public var id: String {
        switch self {
        case .artifact(let artifact): "artifact:\(artifact.id)"
        case .file(let file): "file:\(file.attachmentId)"
        }
    }

    /// Reads the items out of a stored tool result: the artifact tool's
    /// `{artifactId, title, artifactKind, sizeBytes}` and the shell tool's
    /// `{artifacts: [{name, attachmentId, url, contentType, sizeBytes}]}`.
    public static func items(toolName: String, result: String?) -> [ProducedItem] {
        let trimmed = (result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
            let object = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue
        else { return [] }
        switch toolName {
        case "artifact":
            guard let id = object["artifactId"]?.stringValue, !id.isEmpty,
                let kind = object["artifactKind"]?.stringValue.flatMap(ArtifactReference.Kind.init(rawValue:))
            else { return [] }
            return [
                .artifact(
                    ArtifactReference(
                        id: id, title: object["title"]?.stringValue ?? "", kind: kind,
                        sizeBytes: object["sizeBytes"]?.numberValue.map { Int64($0) }))
            ]
        case "shell":
            return (object["artifacts"]?.arrayValue ?? []).compactMap { entry in
                guard let attachmentId = entry["attachmentId"]?.stringValue, !attachmentId.isEmpty else { return nil }
                return .file(
                    ProducedFile(
                        attachmentId: attachmentId, name: entry["name"]?.stringValue ?? attachmentId,
                        contentType: entry["contentType"]?.stringValue ?? "", url: entry["url"]?.stringValue,
                        sizeBytes: entry["sizeBytes"]?.numberValue.map { Int64($0) }))
            }
        default:
            return []
        }
    }
}
