import SwiftUI

/// The large action that leads a detail screen, such as Settle on a debt or Mark as Paid on a bill.
///
/// A full-width filled capsule in the given tint. The icon and the semibold title share one color,
/// the page's background color: white in light mode and black in dark, where the tints are lighter
/// and black reads more clearly on them.
struct WalletActionButton: View {
    let title: String
    var symbol = "checkmark.circle.fill"
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.background)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(tint)
    }
}
