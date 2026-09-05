import SwiftUI
import WalletDomain

struct CategoryNatureBadge: View {
    let nature: CategoryNature

    var body: some View {
        Text(nature.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(nature.tint, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nature: \(nature.title)")
    }
}
