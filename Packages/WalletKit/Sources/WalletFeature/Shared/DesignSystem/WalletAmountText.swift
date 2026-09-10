import SwiftUI
import WalletDomain

/// A formatted money value with the app's sign and tint rules.
///
/// Expenses read as a red minus, income as a green plus, transfers as plain primary text. The sign
/// is presentation only — it is never folded into the stored amount.
struct WalletAmountText: View {
    let amount: Decimal
    let currencyCode: String
    var kind: RecordKind?
    var font: Font = .body.weight(.semibold)
    /// Overrides the kind tint; used where the amount is not a record (balances, budgets, totals).
    var tint: Color?

    private var prefix: String {
        switch kind {
        case .expense: "−"
        case .income: "+"
        default: ""
        }
    }

    private var resolvedTint: Color {
        if let tint { return tint }
        switch kind {
        case .expense: return .red
        case .income: return .green
        default: return .primary
        }
    }

    var body: some View {
        Text(prefix + amount.walletFormatted(currencyCode))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(resolvedTint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

extension WalletAmountText {
    /// A signed total where the sign comes from the value itself, not a record kind.
    /// Positive reads green, negative red, zero stays neutral.
    static func net(_ amount: Decimal, currencyCode: String, font: Font = .body.weight(.semibold)) -> WalletAmountText {
        WalletAmountText(amount: abs(amount), currencyCode: currencyCode,
                         kind: amount > 0 ? .income : amount < 0 ? .expense : nil,
                         font: font,
                         tint: amount == 0 ? .secondary : nil)
    }
}
