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
        Image(systemName: symbols?.symbol(for: category) ?? category.symbol)
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(category.colorToken.color, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}
