import Foundation

/// UploadedFile is a file Portal has stored, as the attachment endpoint returns it.
public struct UploadedFile: Codable, Equatable, Sendable {
    public let id: String
    public let filename: String
    public let contentType: String

    public init(id: String, filename: String, contentType: String) {
        self.id = id
        self.filename = filename
        self.contentType = contentType
    }
}

/// SharePayload builds the text Portal receives for something shared to the
/// app, in the forms the web app uses: a leading block of attachment links
/// for a chat message, and `attachment:<id>` tokens in a ticket description.
public enum SharePayload {
    /// The most the attachment endpoint takes for an ordinary file (32 MiB).
    public static let maximumFileBytes: Int64 = 32 << 20

    /// The message that starts a conversation: one link per file, a blank
    /// line, then the text.
    public static func assistantMessage(text: String, files: [UploadedFile]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !files.isEmpty else { return trimmed }
        let lines = files.map { file -> String in
            let marker = "[Attachment: \(escape(file.filename))](/api/v1/attachment/\(file.id))"
            return isImage(file) ? "!" + marker : marker
        }
        let block = lines.joined(separator: "\n")
        return trimmed.isEmpty ? block : block + "\n\n" + trimmed
    }

    /// A ticket description: the text, then one token per file.
    public static func ticketDescription(text: String, files: [UploadedFile]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippets = files.map { file -> String in
            let name = escape(file.filename)
            return isImage(file) ? "![\(name)](attachment:\(file.id))" : "[\(name)](attachment:\(file.id))"
        }
        return ([trimmed].filter { !$0.isEmpty } + snippets).joined(separator: "\n\n")
    }

    /// A ticket title from shared text: its first line, shortened.
    public static func suggestedTitle(from text: String, limit: Int = 80) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard firstLine.count > limit else { return firstLine }
        return String(firstLine.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// The shared pieces as one text: the words, then each address on its own line.
    public static func combinedText(texts: [String], urls: [URL]) -> String {
        (texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } + urls.map(\.absoluteString)).joined(separator: "\n\n")
    }

    static func isImage(_ file: UploadedFile) -> Bool {
        file.contentType.lowercased().hasPrefix("image/")
    }

    static func escape(_ name: String) -> String {
        var result = ""
        for character in name {
            if "\\[]()".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}

/// MultipartBody writes the body of a file upload to a file on disk, copying
/// the source in small pieces, so a large file is never held in memory.
public enum MultipartBody {
    public static let chunkBytes = 64 * 1024

    /// Writes the body of a one-file multipart form (field `file`) and
    /// returns its length.
    @discardableResult
    public static func write(boundary: String, filename: String, contentType: String, source: URL, to destination: URL) throws -> Int64 {
        let safeName = filename.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var total: Int64 = 0
        func append(_ data: Data) throws {
            try output.write(contentsOf: data)
            total += Int64(data.count)
        }
        try append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        while let chunk = try input.read(upToCount: chunkBytes), !chunk.isEmpty {
            try append(chunk)
        }
        try append(Data("\r\n--\(boundary)--\r\n".utf8))
        return total
    }
}
