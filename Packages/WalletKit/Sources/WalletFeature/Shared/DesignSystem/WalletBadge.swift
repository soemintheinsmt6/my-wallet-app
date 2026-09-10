import SwiftUI

/// A small status capsule. The label always carries the meaning, so color stays supporting.
struct WalletBadge: View {
    let title: String
    var tint: Color = .gray
    /// Reads the state aloud with context, e.g. "Status: Paused".
    var accessibilityPrefix: String?

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, WalletMetrics.small)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityPrefix.map { "\($0): \(title)" } ?? title)
    }
}

#Preview {
    HStack {
        WalletBadge(title: "Active", tint: .green)
        WalletBadge(title: "Paused", tint: .orange)
        WalletBadge(title: "Cancelled", tint: .gray)
    }
    .padding()
}
