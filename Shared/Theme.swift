import SwiftUI

/// The Portal web app's palette as named colors. Each is a color set in
/// Theme.xcassets with a light and a dark value, so no view writes a hex.
/// The accent is the app's AccentColor, which system controls pick up on
/// their own.
extension Color {
    /// The page behind lists and screens: warm cream in light, near-black in dark.
    static let portalPage = Color("PageBackground")
    /// Cards, rows and bubbles that sit on the page: white in light, one step lighter than the page in dark.
    static let portalCard = Color("CardBackground")
    /// Muted icons and secondary chips.
    static let portalSecondary = Color("MujinSecondary")
    /// Text and symbols on an accent fill.
    static let onAccent = Color("AccentContrast")
    /// Status colors, for states an operator must act on and nothing else.
    static let statusSuccess = Color("StatusSuccess")
    static let statusWarning = Color("StatusWarning")
    static let statusError = Color("StatusError")
    /// A critical alarm: darker than an error, and dark enough for white words in both appearances.
    static let statusCritical = Color("StatusCritical")
    static let statusInfo = Color("StatusInfo")
}

/// PortalRows gives every row inside it the card surface, over the page the
/// list shows. It is the list-row counterpart of `portalList()`.
struct PortalRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Group { content }
            .listRowBackground(Color.portalCard)
            .labelStyle(PortalRowLabelStyle())
            // Switches take the accent, not the system green.
            .tint(Color.accentColor)
    }
}

/// InlineLabelStyle is a small mark inside a row: the icon right beside its words, not in the row's icon column.
struct InlineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// PortalRowLabelStyle puts every row icon in one centered column, so a wide
/// symbol and a narrow one line up and the titles start at the same place.
struct PortalRowLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .body) private var iconColumnWidth = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At the accessibility sizes the icon column would leave too little width, and the title would break mid-word.
            configuration.title
        } else {
            HStack(spacing: 12) {
                configuration.icon
                    .frame(width: iconColumnWidth, alignment: .center)
                configuration.title
            }
        }
    }
}

/// PortalNameLineModifier keeps a name or a short label whole. At the accessibility sizes a word that does not
/// fit the row would break mid-word with a hyphen, so the text takes one line and shrinks to fit instead.
struct PortalNameLineModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.lineLimit(1).minimumScaleFactor(0.5)
        } else {
            content
        }
    }
}

extension View {
    /// A name or short label that must never break mid-word at the accessibility text sizes.
    nonisolated func portalNameLine() -> some View {
        modifier(PortalNameLineModifier())
    }

    /// A list at the root of a tab: it also leaves room under its last row for the floating tab bar.
    func portalRootList() -> some View {
        portalList().contentMargins(.bottom, 88, for: .scrollContent)
    }

    /// Shows a list or form on the page color instead of the system's grouped gray.
    func portalList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.portalPage)
            // The floating tab bar's blur must not sit over the last row's text.
            .contentMargins(.bottom, 16, for: .scrollContent)
    }
}
