import SwiftUI

/// ListEnd tells whether a message list shows its end. A list follows what arrives there, a new message or a row that grows,
/// only when it does: a person reading further up keeps the messages they are reading where they are.
enum ListEnd {
    /// How far above the end still counts as at it, so a list a few points short of its end still follows.
    static let toleranceHeight: CGFloat = 40

    static func isShown(_ geometry: ScrollGeometry) -> Bool {
        geometry.visibleRect.maxY >= geometry.contentSize.height - toleranceHeight
    }
}
