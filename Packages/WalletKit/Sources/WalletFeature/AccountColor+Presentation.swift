import SwiftUI
import WalletDomain

extension AccountColor {
    var tint: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }

    var title: String { rawValue.capitalized }
}
