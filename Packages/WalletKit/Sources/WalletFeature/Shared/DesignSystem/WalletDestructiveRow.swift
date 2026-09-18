import SwiftUI

/// A destructive row in a form — red throughout, icon included.
///
/// `Button(role: .destructive)` reddens the title and leaves the icon on the accent colour, and
/// neither a `tint` nor a `foregroundStyle` inside the label changes that while the form's own
/// button style is the thing doing the colouring. Turning that style off and colouring the label
/// directly is what holds. The label is then stretched and given a shape of its own, since a plain
/// button is only tappable where it draws.
struct WalletDestructiveRow: View {
    let title: String
    var symbol = "trash"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
