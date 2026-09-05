import Foundation
import WalletDomain

enum AccountAmountInput {
    static func text(_ amount: Decimal, locale: Locale = .current) -> String {
        amount.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...8)))
    }

    static func parse(_ text: String, locale: Locale = .current) throws -> Decimal {
        let separator = locale.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^[+-]?[0-9]{1,18}(\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            throw AccountValidationError.invalidBalance
        }
        return amount
    }
}
