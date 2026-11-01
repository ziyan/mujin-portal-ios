import Foundation

/// ControllerFilter narrows the staff controller list by what was typed and by site.
public struct ControllerFilter: Equatable, Sendable {
    public var query = ""
    public var siteId: String?

    public init(query: String = "", siteId: String? = nil) {
        self.query = query
        self.siteId = siteId
    }

    /// A controller matches the text when its id, its comment or its site's name holds it.
    public func apply(_ controllers: [ControllerSummary], siteNames: [String: String]) -> [ControllerSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return controllers.filter { controller in
            if let siteId, controller.siteId != siteId { return false }
            guard !text.isEmpty else { return true }
            return controller.id.localizedCaseInsensitiveContains(text) || (controller.comment ?? "").localizedCaseInsensitiveContains(text)
                || (siteNames[controller.siteId ?? ""] ?? "").localizedCaseInsensitiveContains(text)
        }
    }
}
