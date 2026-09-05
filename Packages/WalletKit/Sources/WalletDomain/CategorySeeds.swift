import Foundation

/// Stable IDs, not editable names, determine whether a seed already exists.
public enum CategorySeeds {
    public static let categories: [WalletCategory] = {
        // Preserve existing positions: group/child positions form the stable seed IDs.
        let groups: [(String, CategoryNature, [(String, CategoryNature)])] = [
            ("Food & Drinks", .need, [("Groceries", .need), ("Restaurant", .want), ("Fast Food", .want), ("Bar & Café", .want)]),
            ("Shopping", .want, [("Clothing & Shoes", .need), ("Electronics", .want), ("Personal Care", .need), ("Gifts", .want), ("Household Items", .need)]),
            ("Housing", .must, [("Rent", .must), ("Utilities", .must), ("Maintenance & Repairs", .need), ("Home Insurance", .must), ("Furniture", .need)]),
            ("Transportation", .need, [("Public Transport", .need), ("Taxi & Ride-hailing", .want), ("Train", .need), ("Flights", .want), ("Bicycle", .need)]),
            ("Vehicle", .need, [("Fuel", .need), ("Parking", .need), ("Service & Repairs", .need), ("Vehicle Insurance", .must), ("Registration & Tolls", .must)]),
            ("Life & Entertainment", .want, [("Health & Fitness", .need), ("Hobbies", .want), ("Movies & Events", .want), ("Travel & Holidays", .want), ("Education", .need), ("Subscriptions", .want)]),
            ("Communication (PC)", .need, [("Mobile Phone", .need), ("Internet", .need), ("Software & Apps", .need), ("Cloud Services", .need), ("Computer Accessories", .want)]),
            ("Financial Expenses", .must, [("Bank Fees", .must), ("Loan Interest", .must), ("Taxes", .must), ("Loan Repayments", .must), ("Fines & Penalties", .must)]),
            ("Investments", .need, [("Stocks", .want), ("Bonds", .need), ("Funds", .need), ("Real Estate", .want), ("Retirement Savings", .need)]),
            ("Income", .none, [("Salary", .none), ("Freelance", .none), ("Business Income", .none), ("Interest & Dividends", .none), ("Gifts & Refunds", .none)]),
        ]
        return groups.enumerated().flatMap { index, group -> [WalletCategory] in
            let parentID = seedID(group: index + 1, child: 0)
            let parent = WalletCategory(id: parentID, name: group.0, nature: group.1, sortOrder: index)
            let children = group.2.enumerated().map { childIndex, child in
                WalletCategory(id: seedID(group: index + 1, child: childIndex + 1), parentID: parentID, name: child.0, nature: child.1, sortOrder: childIndex)
            }
            return [parent] + children
        }
    }()

    private static func seedID(group: Int, child: Int) -> UUID {
        UUID(uuidString: String(format: "CA7E6000-0000-4000-8000-%06d%06d", group, child))!
    }
}
