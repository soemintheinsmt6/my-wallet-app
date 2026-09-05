import WalletDomain
import SwiftUI

extension CategoryNature {
    var tint: Color {
        switch self {
        case .none: .gray
        case .must: .green
        case .need: .blue
        case .want: .red
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .must: "Must"
        case .need: "Need"
        case .want: "Want"
        }
    }
}
