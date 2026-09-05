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
        case .other: "wallet.bifold"
        }
    }
}
