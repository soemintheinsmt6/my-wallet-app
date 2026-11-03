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

    public init(currentBalance: Decimal = 0, color: AccountColor = .blue, notifyBelowMinimum: Bool = false, minimumBalance: Decimal = 0, notifyAboveMaximum: Bool = false, maximumBalance: Decimal = 0, excludeFromStats: Bool = false, symbol: String? = nil) {
        self.currentBalance = currentBalance
        self.color = color
        self.notifyBelowMinimum = notifyBelowMinimum
        self.minimumBalance = minimumBalance
        self.notifyAboveMaximum = notifyAboveMaximum
        self.maximumBalance = maximumBalance
        self.excludeFromStats = excludeFromStats
        self.symbol = symbol
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
