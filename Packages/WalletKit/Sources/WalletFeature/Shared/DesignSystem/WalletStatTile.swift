import SwiftUI

/// A compact labelled figure used in the Home summary and the Statistics header.
///
/// Sits on the grouped-list secondary surface rather than a custom card so it keeps the system's
/// light/dark treatment and elevation.
struct WalletStatTile: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack(spacing: WalletMetrics.tight) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WalletMetrics.medium)
        // Sits on a cleared list row so the grouped page background reads as the gap between tiles.
        .background(.background, in: RoundedRectangle(cornerRadius: WalletMetrics.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// A list section header carrying an optional trailing action, matching the system header's
/// uppercase footnote treatment.
struct WalletSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: WalletMetrics.small)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
            }
        }
    }
}

#Preview {
    HStack(spacing: WalletMetrics.medium) {
        WalletStatTile(title: "Income", value: "$3,200.00", symbol: "arrow.down.left", tint: .green)
        WalletStatTile(title: "Expenses", value: "$1,842.50", symbol: "arrow.up.right", tint: .red)
    }
    .padding()
}
