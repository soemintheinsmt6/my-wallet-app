import SwiftUI

extension Color {
    /// The fill of a card sitting on a grouped list's background: the same surface the list draws
    /// behind its own rows, so tiles placed on a clear row match the cards around them. White on
    /// the light gray background, and a raised dark gray on the black one in dark mode, where the
    /// plain `background` color would be black and the tile would vanish.
    static var walletCard: Color {
        #if os(iOS) || os(visionOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.2)
        #endif
    }
}
