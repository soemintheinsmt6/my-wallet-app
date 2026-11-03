import WalletDomain

extension AccountType {
    var title: String {
        switch self {
        case .cash: "Cash"
        case .checking: "Checking Account"
        case .creditCard: "Credit Card"
        case .savings: "Savings Account"
        case .investments: "Investments"
        case .loansAndMortgage: "Loans & Mortgage"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .cash: "banknote"
        case .checking: "building.columns"
        case .creditCard: "creditcard"
        case .savings: "tray.full"
        case .investments: "chart.line.uptrend.xyaxis"
        case .loansAndMortgage: "house"
        case .other: WalletSymbols.wallet
        }
    }

    /// What the type's number is called, for the editor field and the detail row.
    var accountNumberTitle: String {
        switch self {
        case .creditCard: "Card Number"
        case .loansAndMortgage: "Loan Number"
        case .cash, .checking, .savings, .investments, .other: "Account Number"
        }
    }
}

extension Account {
    /// The account's chosen icon, or its type's when none is chosen.
    var symbol: String { settings.symbol ?? type.symbol }

    /// The masked number, e.g. "•••• 1234", or `nil` when there is none.
    var maskedAccountNumber: String? {
        guard type.hasAccountNumber, let number = settings.accountNumber else { return nil }
        return AccountNumber.masked(number)
    }
}
