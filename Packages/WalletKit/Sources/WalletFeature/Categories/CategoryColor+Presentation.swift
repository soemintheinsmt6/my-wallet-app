import SwiftUI
import WalletDomain

public extension CategoryColor {
    /// Use this same conversion for chart marks and legends.
    var color: Color {
        Color(.sRGB, red: Double((rawValue >> 16) & 0xFF) / 255,
              green: Double((rawValue >> 8) & 0xFF) / 255,
              blue: Double(rawValue & 0xFF) / 255, opacity: 1)
    }
}

/// A category's tile: its chosen icon, or the starter one, in its color. The icon is part of the
/// category, so a new choice redraws every tile as soon as the categories reload.
///
/// Drawn by the shared tile, so category icons get the same gradient fill, symbol weight and
/// corners as account, record-kind and menu icons; a flat fill read duller beside them even in
/// the same hue.
struct CategoryIcon: View {
    let category: WalletCategory

    var body: some View {
        WalletIconTile(symbol: category.symbol, color: category.colorToken.color)
    }
}
