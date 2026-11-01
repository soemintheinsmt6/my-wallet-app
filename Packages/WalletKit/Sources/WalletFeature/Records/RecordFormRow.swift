import SwiftUI
import WalletDomain

struct RecordFormRow<Content: View>: View {
    let symbol: String
    var color: Color = .gray
    var category: WalletCategory?
    var categoryTile = false
    var filledIcon = false
    /// The last row of a section has nothing to separate it from, so it drops its rule.
    var showsDivider = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if categoryTile, let category = category {
                    CategoryIcon(category: category)
                } else if categoryTile || filledIcon {
                    WalletIconTile(symbol: symbol, color: color)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                }
                HStack { content() }
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            if showsDivider { Divider().padding(.leading, 66) }
        }

    }
}
