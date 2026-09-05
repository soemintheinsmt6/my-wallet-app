import Foundation
import WalletDomain

extension WalletCategory {
    /// Seed icons follow stable identity even after renaming. Custom children use their parent's icon.
    var symbol: String {
        CategorySymbols.byID[id]
            ?? CategorySymbols.byName[name]
            ?? parentID.flatMap { CategorySymbols.byID[$0] }
            ?? "tag"
    }
}

private enum CategorySymbols {
    static let byID: [UUID: String] = Dictionary(uniqueKeysWithValues: CategorySeeds.categories.map {
        ($0.id, byName[$0.name] ?? "tag")
    })

    static let byName: [String: String] = [
        "Food & Drinks": "fork.knife",
        "Groceries": "basket",
        "Restaurant": "fork.knife",
        "Fast Food": "takeoutbag.and.cup.and.straw",
        "Bar & Café": "cup.and.saucer",
        "Shopping": "bag",
        "Clothing & Shoes": "tshirt",
        "Electronics": "desktopcomputer",
        "Personal Care": "comb",
        "Gifts": "gift",
        "Household Items": "lamp.table",
        "Housing": "house",
        "Rent": "key",
        "Utilities": "bolt",
        "Maintenance & Repairs": "hammer",
        "Home Insurance": "shield",
        "Furniture": "sofa",
        "Transportation": "bus",
        "Public Transport": "bus",
        "Taxi & Ride-hailing": "car",
        "Train": "tram",
        "Flights": "airplane",
        "Bicycle": "bicycle",
        "Vehicle": "car",
        "Fuel": "fuelpump",
        "Parking": "parkingsign.circle",
        "Service & Repairs": "wrench.and.screwdriver",
        "Vehicle Insurance": "car.side",
        "Registration & Tolls": "doc.text",
        "Life & Entertainment": "theatermasks",
        "Health & Fitness": "heart",
        "Hobbies": "paintpalette",
        "Movies & Events": "film",
        "Travel & Holidays": "suitcase",
        "Education": "graduationcap",
        "Subscriptions": "play.rectangle",
        "Communication (PC)": "laptopcomputer",
        "Mobile Phone": "iphone",
        "Internet": "wifi",
        "Software & Apps": "app",
        "Cloud Services": "icloud",
        "Computer Accessories": "keyboard",
        "Financial Expenses": "banknote",
        "Bank Fees": "building.columns",
        "Loan Interest": "percent",
        "Taxes": "doc.text",
        "Loan Repayments": "creditcard",
        "Fines & Penalties": "exclamationmark.triangle",
        "Investments": "chart.line.uptrend.xyaxis",
        "Stocks": "chart.bar",
        "Bonds": "doc.plaintext",
        "Funds": "chart.pie",
        "Real Estate": "building.2",
        "Retirement Savings": "clock",
        "Income": "arrow.down.circle",
        "Salary": "briefcase",
        "Freelance": "laptopcomputer",
        "Business Income": "storefront",
        "Interest & Dividends": "percent",
        "Gifts & Refunds": "gift",
    ]
}
