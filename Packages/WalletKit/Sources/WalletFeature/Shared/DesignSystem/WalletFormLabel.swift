import SwiftUI

/// A form row's title led by a colored symbol, as the record editor leads its rows. Used by the
/// grouped editors (debts, goals) so their rows read like the record editor's.
struct WalletFormLabel: View {
    let title: String
    let symbol: String
    let color: Color

    init(_ title: String, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label { Text(title) } icon: { WalletFormIcon(symbol: symbol, color: color) }
    }
}

/// The colored symbol alone, for rows whose content is a field rather than a title.
struct WalletFormIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
    }
}
