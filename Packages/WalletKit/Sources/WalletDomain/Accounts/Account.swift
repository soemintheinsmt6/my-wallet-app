import Foundation

public enum AccountType: String, CaseIterable, Codable, Sendable, Identifiable {
    case cash
    case checking
    case creditCard
    case savings
    case investments
    case loansAndMortgage
    case other

    public var id: String { rawValue }

    /// Every type but cash is held somewhere that numbers it: a bank, card issuer, broker or lender.
    public var hasAccountNumber: Bool { self != .cash }
}

/// Rules for the optional account number. It is stored whole so it can be copied, but shown masked
/// everywhere except the editor.
public enum AccountNumber {
    /// IBAN, the longest common format, runs to 34 characters.
    public static let maximumLength = 34

    /// Trims the input, and treats an empty one as no number.
    public static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Letters, digits, spaces and dashes, as bank, card, IBAN and loan numbers are written.
    public static func isValid(_ number: String) -> Bool {
        guard number.count <= maximumLength else { return false }
        return number.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-")
        }
    }

    /// The last four letters or digits behind a mask, e.g. "•••• 1234", so lists can tell accounts
    /// apart without showing the number.
    public static func masked(_ number: String) -> String {
        let characters = number.filter { $0.isLetter || $0.isNumber }
        return "•••• " + String(characters.suffix(4))
    }
}

public struct Account: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let type: AccountType
    public let createdAt: Date
    public let currencyCode: String
    public let settings: AccountSettings

    public init(id: UUID = UUID(), name: String, type: AccountType, createdAt: Date = Date(), currencyCode: String = "USD", settings: AccountSettings = AccountSettings()) {
        self.id = id
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.currencyCode = currencyCode
        self.settings = settings
    }
}

public enum AccountColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case blue, teal, green, yellow, orange, red, pink, purple, indigo, gray
    public var id: String { rawValue }
}

public struct AccountSettings: Equatable, Sendable {
    public var currentBalance: Decimal
    public var color: AccountColor
    public var notifyBelowMinimum: Bool
    public var minimumBalance: Decimal
    public var notifyAboveMaximum: Bool
    public var maximumBalance: Decimal
    public var excludeFromStats: Bool
    /// An SF Symbol chosen for the account. `nil` leaves the icon to the account's type.
    public var symbol: String?
    /// The bank, card or loan number, stored whole and shown masked outside the editor. `nil` when
    /// none is entered, and always `nil` for cash.
    public var accountNumber: String?

    public init(currentBalance: Decimal = 0, color: AccountColor = .blue, notifyBelowMinimum: Bool = false, minimumBalance: Decimal = 0, notifyAboveMaximum: Bool = false, maximumBalance: Decimal = 0, excludeFromStats: Bool = false, symbol: String? = nil, accountNumber: String? = nil) {
        self.currentBalance = currentBalance
        self.color = color
        self.notifyBelowMinimum = notifyBelowMinimum
        self.minimumBalance = minimumBalance
        self.notifyAboveMaximum = notifyAboveMaximum
        self.maximumBalance = maximumBalance
        self.excludeFromStats = excludeFromStats
        self.symbol = symbol
        self.accountNumber = accountNumber
    }

    public var isBelowMinimum: Bool { notifyBelowMinimum && currentBalance < minimumBalance }
    public var isAboveMaximum: Bool { notifyAboveMaximum && currentBalance > maximumBalance }
}

public extension Array where Element == Account {
    /// The currency a summary opens in: the user's main currency when an account holds it,
    /// otherwise the currency most accounts use (alphabetical on a tie), or `nil` with no accounts.
    func preferredCurrency(default defaultCurrency: String) -> String? {
        if contains(where: { $0.currencyCode == defaultCurrency }) { return defaultCurrency }
        let counts = Dictionary(grouping: self, by: \.currencyCode).mapValues(\.count)
        return counts.max { left, right in
            left.value == right.value ? left.key > right.key : left.value < right.value
        }?.key
    }
}
