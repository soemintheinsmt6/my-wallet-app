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

struct CategoryIcon: View {
    let category: WalletCategory

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(category.colorToken.color, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}
