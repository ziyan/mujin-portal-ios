import Foundation

/// PasteRule decides what a Paste into a message composer does when the
/// clipboard holds pictures: how many become attachments and whether the text
/// that came with them is also typed into the message.
///
/// Copying a picture from a browser, Photos, Messages, Mail or a screenshot
/// often puts text on the clipboard beside it: the picture's address, its file
/// name, or a caption. Like Messages, a Paste with pictures attaches them
/// (as many as the message has room for). The text is typed in only when it
/// says something of its own. A lone address or file name that merely names
/// the picture is dropped, because the attachment already is that picture.
/// Anything else, such as a copied sentence, a caption or an address inside a
/// sentence or a name with words and no number in it, is kept: losing words the person copied is worse than one extra
/// line they can delete.
public enum PasteRule {
    /// What to do with one Paste.
    public struct Decision: Equatable, Sendable {
        /// How many of the pasted pictures to attach.
        public let attachmentCount: Int
        /// The text to type into the message; nil when there is none or it only names a picture.
        public let textToInsert: String?
        /// Why some pictures were left out, in words for the person; nil when all fit.
        public let refusal: String?
    }

    /// File name endings that mark a line as the name of a picture.
    public static let pictureFileExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp"]

    /// The address schemes that count as a picture's own address when alone on the clipboard.
    private static let addressSchemes: Set<String> = ["http", "https", "file", "data", "blob", "content"]

    /// How many pictures fit in the message: the room left under the limit on files per message.
    public static func attachableCount(pictureCount: Int, alreadyAttached: Int) -> Int {
        max(0, min(pictureCount, AttachmentLimits.maximumFileCount - alreadyAttached))
    }

    /// Decides one Paste. `pictureCount` is the number of pictures on the clipboard, `texts` the strings that came
    /// with them, `pictureNames` the file names the pictures carry (may be empty), and `alreadyAttached` the files
    /// already in the message, counting pictures still being read.
    public static func decide(pictureCount: Int, texts: [String], pictureNames: [String] = [], alreadyAttached: Int) -> Decision {
        let text = combinedText(texts)
        guard pictureCount > 0 else {
            return Decision(attachmentCount: 0, textToInsert: text.isEmpty ? nil : text, refusal: nil)
        }
        let count = attachableCount(pictureCount: pictureCount, alreadyAttached: alreadyAttached)
        let refusal = count < pictureCount
            ? AttachmentLimits.refusal(name: "", byteCount: 0, alreadyAttached: AttachmentLimits.maximumFileCount) : nil
        let isPictureReference = text.isEmpty || isOnlyPictureReference(text, pictureNames: pictureNames)
        return Decision(attachmentCount: count, textToInsert: isPictureReference ? nil : text, refusal: refusal)
    }

    /// The clipboard strings as one text: blank ones dropped, repeats of the same string kept once, in order.
    public static func combinedText(_ texts: [String]) -> String {
        var seen: [String] = []
        for text in texts where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !seen.contains(text) {
            seen.append(text)
        }
        return seen.joined(separator: "\n")
    }

    /// True when every line of the text is an address or a file name that only points at a picture.
    public static func isOnlyPictureReference(_ text: String, pictureNames: [String] = []) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { isPictureReference($0, pictureNames: pictureNames) }
    }

    private static func isPictureReference(_ line: String, pictureNames: [String]) -> Bool {
        if isAddress(line) { return true }
        let lowercased = line.lowercased()
        for name in pictureNames where !name.isEmpty {
            let lowercasedName = name.lowercased()
            if lowercased == lowercasedName || lowercased == stem(of: lowercasedName) { return true }
        }
        guard line.count <= 255, pictureFileExtensions.contains(fileExtension(of: lowercased)) else { return false }
        // A name with spaces counts only in the screenshot and camera style, which has a date or number in it;
        // "Please use the file named logo.png" is a sentence that happens to end in a file name.
        return !line.contains(where: \.isWhitespace) || stem(of: lowercased).contains(where: \.isNumber)
    }

    private static func isAddress(_ line: String) -> Bool {
        guard !line.contains(where: \.isWhitespace) else { return false }
        if line.lowercased().hasPrefix("www."), line.contains(".") { return true }
        guard let url = URL(string: line), let scheme = url.scheme?.lowercased(), addressSchemes.contains(scheme) else { return false }
        if scheme == "http" || scheme == "https" { return !(url.host ?? "").isEmpty }
        return true
    }

    private static func fileExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }

    private static func stem(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}
