import SwiftUI
import WalletDomain

extension RecordKind {
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        }
    }
    var tint: Color {
        switch self {
        case .expense: .red
        case .income: .green
        case .transfer: .blue
        }
    }
}

extension RecordDraft {
    /// Adjustments get their own icon, so they read apart from category-filed income and expenses.
    static let adjustmentSymbol = "plusminus"
    static let adjustmentTint = Color.orange
}

/// The two directions of a balance adjustment, mapped onto the kinds they are stored as.
extension RecordKind {
    var adjustmentTitle: String { self == .income ? "Increase" : "Decrease" }
}

extension PaymentType {
    var title: String {
        switch self {
        case .unspecified: "Not specified"
        case .cash: "Cash"
        case .debitCard: "Debit Card"
        case .creditCard: "Credit Card"
        case .bankTransfer: "Bank Transfer"
        case .mobilePayment: "Mobile Payment"
        case .cheque: "Cheque"
        case .other: "Other"
        }
    }
}
