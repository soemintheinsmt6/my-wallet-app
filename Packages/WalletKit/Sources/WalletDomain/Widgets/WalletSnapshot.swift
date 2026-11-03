import Foundation

/// A small, self-contained summary of the wallet that the widget extension can read.
///
/// Widgets run in a separate process and must render fast and offline. Rather than opening the
/// SwiftData/CloudKit store from the extension — which would mean relocating the store into a
/// shared App Group container and migrating existing users' data — the app writes this value to
/// the shared container whenever its data changes, and the widget only ever reads it.
///
/// Everything here is already resolved for display: symbols, colors and titles are computed by the
/// app, so the extension needs no presentation logic and no access to categories or accounts.
public struct WalletSnapshot: Codable, Sendable, Equatable {
    /// Totals are never combined across currencies; each currency stands on its own.
    public struct Balance: Codable, Sendable, Equatable, Identifiable {
        public let currencyCode: String
        public let total: Decimal
        public let accountCount: Int

        public var id: String { currencyCode }

        public init(currencyCode: String, total: Decimal, accountCount: Int) {
            self.currencyCode = currencyCode
            self.total = total
            self.accountCount = accountCount
        }
    }

    public struct Month: Codable, Sendable, Equatable {
        public let currencyCode: String
        public let start: Date
        public let income: Decimal
        public let expenses: Decimal

        public var net: Decimal { income - expenses }

        public init(currencyCode: String, start: Date, income: Decimal, expenses: Decimal) {
            self.currencyCode = currencyCode
            self.start = start
            self.income = income
            self.expenses = expenses
        }
    }

    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let subtitle: String
        public let amount: Decimal
        public let currencyCode: String
        public let kind: RecordKind
        public let date: Date
        public let symbol: String
        /// sRGB value from `CategoryColor`, or `nil` when the record has no category.
        public let colorValue: UInt32?

        public init(id: UUID, title: String, subtitle: String, amount: Decimal, currencyCode: String,
                    kind: RecordKind, date: Date, symbol: String, colorValue: UInt32?) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.amount = amount
            self.currencyCode = currencyCode
            self.kind = kind
            self.date = date
            self.symbol = symbol
            self.colorValue = colorValue
        }
    }

    public struct BudgetProgressSummary: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let spent: Decimal
        public let limit: Decimal
        public let currencyCode: String
        public let status: String

        /// Clamped for meters; `spent`/`limit` remain exact for the text beside them.
        public var fraction: Double {
            guard limit > 0 else { return 0 }
            let value = NSDecimalNumber(decimal: spent / limit).doubleValue
            return min(1, max(0, value))
        }

        public var isOverBudget: Bool { spent >= limit && limit > 0 }

        public init(id: UUID, name: String, spent: Decimal, limit: Decimal, currencyCode: String, status: String) {
            self.id = id
            self.name = name
            self.spent = spent
            self.limit = limit
            self.currencyCode = currencyCode
            self.status = status
        }
    }

    /// A pickable account or category, carried so the watch can add a record without the store.
    public struct Option: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let title: String
        public let symbol: String
        public let colorValue: UInt32?
        /// Only accounts carry a currency.
        public let currencyCode: String?

        public init(id: UUID, title: String, symbol: String, colorValue: UInt32? = nil,
                    currencyCode: String? = nil) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.colorValue = colorValue
            self.currencyCode = currencyCode
        }
    }

    public let generatedAt: Date
    public let balances: [Balance]
    public let month: Month?
    public let recent: [Entry]
    public let budgets: [BudgetProgressSummary]
    /// Accounts and most-used expense categories, for quick entry away from the store.
    public let accounts: [Option]
    public let quickCategories: [Option]
    /// Spending so far today, in the leading currency.
    public let todaySpend: Decimal
    /// The app's Count Large Amounts In choice, so compact figures read the same everywhere.
    public let numberScale: NumberScale

    public init(generatedAt: Date = Date(), balances: [Balance] = [], month: Month? = nil,
                recent: [Entry] = [], budgets: [BudgetProgressSummary] = [],
                accounts: [Option] = [], quickCategories: [Option] = [],
                todaySpend: Decimal = 0, numberScale: NumberScale = .automatic) {
        self.generatedAt = generatedAt
        self.balances = balances
        self.month = month
        self.recent = recent
        self.budgets = budgets
        self.accounts = accounts
        self.quickCategories = quickCategories
        self.todaySpend = todaySpend
        self.numberScale = numberScale
    }

    /// Decoded field by field so a snapshot written by an older build — one without the quick-add
    /// fields — still loads instead of failing and blanking every widget.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        balances = try container.decodeIfPresent([Balance].self, forKey: .balances) ?? []
        month = try container.decodeIfPresent(Month.self, forKey: .month)
        recent = try container.decodeIfPresent([Entry].self, forKey: .recent) ?? []
        budgets = try container.decodeIfPresent([BudgetProgressSummary].self, forKey: .budgets) ?? []
        accounts = try container.decodeIfPresent([Option].self, forKey: .accounts) ?? []
        quickCategories = try container.decodeIfPresent([Option].self, forKey: .quickCategories) ?? []
        todaySpend = try container.decodeIfPresent(Decimal.self, forKey: .todaySpend) ?? 0
        // Read as text so a scale added by a newer build falls back instead of failing the decode.
        let scale = try container.decodeIfPresent(String.self, forKey: .numberScale)
        numberScale = scale.flatMap(NumberScale.init(rawValue:)) ?? .automatic
    }

    public var isEmpty: Bool { balances.isEmpty && recent.isEmpty && budgets.isEmpty }

    /// The currency the widgets lead with: the one holding the most accounts, ties broken by code
    /// so the choice never flickers between refreshes.
    public var primaryBalance: Balance? {
        balances.max { left, right in
            left.accountCount == right.accountCount ? left.currencyCode > right.currencyCode
                                                    : left.accountCount < right.accountCount
        }
    }

    /// A pending expense the watch captured, sent to the phone to be written.
    ///
    /// Carried here so both sides share one definition; the watch never writes to the wallet
    /// itself, because the store lives on the phone.
    public struct QuickExpense: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let amount: Decimal
        public let accountID: UUID
        public let categoryID: UUID?
        public let date: Date

        public init(id: UUID = UUID(), amount: Decimal, accountID: UUID,
                    categoryID: UUID? = nil, date: Date = Date()) {
            self.id = id
            self.amount = amount
            self.accountID = accountID
            self.categoryID = categoryID
            self.date = date
        }
    }

    /// Placeholder content for widget galleries and previews, so an unconfigured widget still
    /// shows its real shape rather than an empty frame.
    public static let preview = WalletSnapshot(
        balances: [Balance(currencyCode: "USD", total: Decimal(string: "12480.55")!, accountCount: 3)],
        month: Month(currencyCode: "USD", start: Date(),
                     income: Decimal(string: "3200")!, expenses: Decimal(string: "1842.50")!),
        recent: [
            Entry(id: UUID(), title: "Restaurant", subtitle: "Cash", amount: Decimal(string: "18")!,
                  currencyCode: "USD", kind: .expense, date: Date(), symbol: "fork.knife",
                  colorValue: CategoryColor.food.rawValue),
            Entry(id: UUID(), title: "Salary", subtitle: "Checking", amount: Decimal(string: "1200")!,
                  currencyCode: "USD", kind: .income, date: Date().addingTimeInterval(-86_400),
                  symbol: "briefcase", colorValue: CategoryColor.income.rawValue),
            Entry(id: UUID(), title: "Transport", subtitle: "Visa", amount: Decimal(string: "24.50")!,
                  currencyCode: "USD", kind: .expense, date: Date().addingTimeInterval(-90_000),
                  symbol: "bus", colorValue: CategoryColor.transportation.rawValue),
        ],
        budgets: [
            BudgetProgressSummary(id: UUID(), name: "Groceries", spent: Decimal(string: "420")!,
                                  limit: Decimal(string: "600")!, currencyCode: "USD", status: "Within budget"),
        ])
}
