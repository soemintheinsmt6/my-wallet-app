import Foundation

public enum BudgetPeriod: String, CaseIterable, Codable, Sendable { case weekly, monthly, custom }

public struct Budget: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var amount: Decimal
    public var currencyCode: String
    public var categoryID: UUID?
    public var period: BudgetPeriod
    public var startDate: Date
    public var endDate: Date
    public var rollover: Bool
    public var notificationsEnabled: Bool
    public var timeZoneIdentifier: String

    public init(id: UUID = UUID(), name: String = "Budget", amount: Decimal = 0, currencyCode: String = "USD",
                categoryID: UUID? = nil, period: BudgetPeriod = .monthly, startDate: Date = Date(),
                endDate: Date = Date().addingTimeInterval(86400 * 30), rollover: Bool = false, notificationsEnabled: Bool = false,
                timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.id = id; self.name = name; self.amount = amount; self.currencyCode = currencyCode
        self.categoryID = categoryID; self.period = period; self.startDate = startDate; self.endDate = endDate
        self.rollover = rollover; self.notificationsEnabled = notificationsEnabled; self.timeZoneIdentifier = timeZoneIdentifier
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw PlanningError.invalidName }
        try RecordDraft.validateAmount(amount)
        guard Locale.commonISOCurrencyCodes.contains(currencyCode), startDate.timeIntervalSince1970.isFinite,
              endDate.timeIntervalSince1970.isFinite, TimeZone(identifier: timeZoneIdentifier) != nil,
              period != .custom || endDate.timeIntervalSince(startDate) >= 86400 else { throw PlanningError.invalidBudget }
    }

    public func interval(index: Int) -> DateInterval? {
        guard index >= 0 else { return nil }
        if period == .custom { return index == 0 ? DateInterval(start: startDate, end: endDate) : nil }
        let rule = RecurrenceRule(frequency: period == .weekly ? .weekly : .monthly, timeZoneIdentifier: timeZoneIdentifier)
        guard let start = rule.date(start: startDate, index: index), let end = rule.date(start: startDate, index: index + 1) else { return nil }
        return DateInterval(start: start, end: end)
    }
}

public struct BudgetProgress: Identifiable, Sendable {
    public let budget: Budget
    public let interval: DateInterval
    public let spent: Decimal
    public let carried: Decimal
    public var id: UUID { budget.id }
    public var limit: Decimal { budget.amount + carried }
    public var remaining: Decimal { limit - spent }
    public var ratio: Double { limit > 0 ? NSDecimalNumber(decimal: spent / limit).doubleValue : 0 }
    public var status: String { spent >= limit ? "Over budget" : ratio >= 0.8 ? "Approaching limit" : "Within budget" }

    /// `ownerShares` maps a split record to the owner's own share, so a bill they fronted for a
    /// group counts toward their budget only for their part of it.
    public static func calculate(budget: Budget, records: [WalletRecord], accounts: [Account],
                                 categories: [WalletCategory], now: Date,
                                 ownerShares: [UUID: Decimal] = [:]) -> BudgetProgress? {
        guard now >= budget.startDate else { return nil }
        let accountIDs = Set(accounts.filter { !$0.settings.excludeFromStats && $0.currencyCode == budget.currencyCode }.map(\.id))
        let categoryIDs = Set(categories.filter { $0.id == budget.categoryID || $0.parentID == budget.categoryID }.map(\.id))
        let expenses = records.filter {
            $0.draft.kind == .expense && $0.draft.countsAsActivity && $0.draft.accountID.map { accountIDs.contains($0) } == true &&
                (budget.categoryID == nil || $0.draft.categoryID.map { categoryIDs.contains($0) } == true)
        }
        var carried: Decimal = 0
        for index in 0..<100_000 {
            guard let interval = budget.interval(index: index) else { return nil }
            let spent = expenses.filter { $0.draft.date >= interval.start && $0.draft.date < interval.end && $0.draft.date <= now }
                .reduce(Decimal.zero) { total, record in
                    total + (ownerShares[record.id] ?? record.draft.amount)
                }
            if now < interval.end { return BudgetProgress(budget: budget, interval: interval, spent: spent, carried: carried) }
            carried = budget.rollover ? max(0, budget.amount + carried - spent) : 0
        }
        return nil
    }
}

@MainActor
public protocol BudgetRepository: AnyObject {
    func fetchBudgets() async throws -> [Budget]
    func saveBudget(_ budget: Budget) async throws
    func deleteBudget(id: UUID) async throws
    func changes() -> AsyncStream<Void>
}

@MainActor
public struct BudgetUseCases {
    private let repository: any BudgetRepository
    public init(repository: any BudgetRepository) { self.repository = repository }
    public func load() async throws -> [Budget] { try await repository.fetchBudgets() }
    public func save(_ budget: Budget) async throws {
        try budget.validate()
        try Task.checkCancellation()
        try await repository.saveBudget(budget)
    }
    public func delete(id: UUID) async throws { try await repository.deleteBudget(id: id) }
}
