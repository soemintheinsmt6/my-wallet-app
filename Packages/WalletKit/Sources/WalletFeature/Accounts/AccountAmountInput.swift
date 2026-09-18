import Foundation
import WalletDomain

enum AccountAmountInput {
    static func text(_ amount: Decimal, locale: Locale = .current) -> String {
        amount.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...8)))
    }

    /// An untouched amount field is a zero rather than a mistake: it shows a "0" placeholder, and
    /// an account opened without a balance is the ordinary case, not one to refuse to save.
    static func parseAllowingEmpty(_ text: String, locale: Locale = .current) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : try parse(trimmed, locale: locale)
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
