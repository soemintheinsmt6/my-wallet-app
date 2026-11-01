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

/// Reaches every category tile so a custom icon applies everywhere at once.
private struct CategorySymbolStoreKey: EnvironmentKey {
    static let defaultValue: CategorySymbolStore? = nil
}

public extension EnvironmentValues {
    var categorySymbolStore: CategorySymbolStore? {
        get { self[CategorySymbolStoreKey.self] }
        set { self[CategorySymbolStoreKey.self] = newValue }
    }
}

struct CategoryIcon: View {
    let category: WalletCategory
    @Environment(\.categorySymbolStore) private var symbols

    var body: some View {
        // An environment object is only read, not observed, so a new icon choice would not redraw
        // tiles already on screen; the observing tile does.
        if let symbols {
            ObservingCategoryIcon(category: category, symbols: symbols)
        } else {
            CategoryIconTile(symbol: category.symbol, color: category.colorToken.color)
        }
    }
}

private struct ObservingCategoryIcon: View {
    let category: WalletCategory
    @ObservedObject var symbols: CategorySymbolStore

    var body: some View {
        CategoryIconTile(symbol: symbols.symbol(for: category), color: category.colorToken.color)
    }
}

/// Drawn by the shared tile, so category icons get the same gradient fill, symbol weight and
/// corners as account, record-kind and menu icons; a flat fill read duller beside them even in
/// the same hue.
private struct CategoryIconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        WalletIconTile(symbol: symbol, color: color)
    }
}
