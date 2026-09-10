import SwiftUI

/// The one leading-icon treatment in the app: a white symbol on a solid color tile.
///
/// Records, categories, accounts, labels and planning rows all use this so their leading edges and
/// text gaps align. Pass `large: true` for header and detail placements.
struct WalletIconTile: View {
    let symbol: String
    var color: Color = .gray
    var large = false

    private var size: CGFloat { large ? WalletMetrics.Tile.largeSize : WalletMetrics.Tile.size }
    private var symbolSize: CGFloat { large ? WalletMetrics.Tile.largeSymbol : WalletMetrics.Tile.symbol }
    private var radius: CGFloat { large ? WalletMetrics.Tile.largeRadius : WalletMetrics.Tile.radius }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A trailing chevron matching the weight the system uses in `NavigationLink` rows.
struct WalletDisclosure: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: WalletMetrics.medium) {
        WalletIconTile(symbol: "fork.knife", color: .green)
        WalletIconTile(symbol: "bus", color: .orange)
        WalletIconTile(symbol: "briefcase", color: .blue, large: true)
        WalletDisclosure()
    }
    .padding()
}
