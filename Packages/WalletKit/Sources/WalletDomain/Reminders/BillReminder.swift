import Foundation

public struct BillReminder: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var amount: Decimal
    public var currencyCode: String
    public var dueDate: Date
    public var recurrence: RecurrenceRule?
    public var nextIndex: Int
    public var accountID: UUID?
    public var categoryID: UUID?
    public var reminderDaysBefore: Int
    public var notificationsEnabled: Bool
    public var isPaid: Bool

    public init(id: UUID = UUID(), name: String = "", amount: Decimal = 0, currencyCode: String = "USD", dueDate: Date = Date(),
                recurrence: RecurrenceRule? = nil, accountID: UUID? = nil, categoryID: UUID? = nil,
                reminderDaysBefore: Int = 1, notificationsEnabled: Bool = false) {
        self.id = id; self.name = name; self.amount = amount; self.currencyCode = currencyCode; self.dueDate = dueDate
        self.recurrence = recurrence; self.accountID = accountID; self.categoryID = categoryID
        self.reminderDaysBefore = reminderDaysBefore; self.notificationsEnabled = notificationsEnabled
        nextIndex = 0; isPaid = false
    }

    public var nextDueDate: Date? {
        guard !isPaid else { return nil }
        return recurrence?.date(start: dueDate, index: nextIndex) ?? (nextIndex == 0 ? dueDate : nil)
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw PlanningError.invalidName }
        try RecordDraft.validateAmount(amount)
        guard accountID != nil else { throw PlanningError.missingAccount }
        guard categoryID != nil else { throw PlanningError.missingCategory }
        try recurrence?.validate(start: dueDate)
        guard Locale.commonISOCurrencyCodes.contains(currencyCode), dueDate.timeIntervalSince1970.isFinite,
              (0...30).contains(reminderDaysBefore), nextIndex >= 0 else { throw PlanningError.invalidReminder }
    }
}

/// How many bills fall due in a period and how many of them are paid, such as "3 of 5 paid this
/// month". Each occurrence due in the period counts once, so a weekly bill counts four or five times
/// in a month. Occurrences are paid in order, so occurrence `n` is paid exactly when `n` is below
/// the bill's `nextIndex`.
public struct BillPeriodProgress: Equatable, Sendable {
    public let dueCount: Int
    public let paidCount: Int
    /// Amounts due and paid, in `currencyCode`; `nil` when the period's bills span several
    /// currencies, which are never added together.
    public let dueAmount: Decimal?
    public let paidAmount: Decimal?
    public let currencyCode: String?

    /// The share of occurrences paid, 0 when nothing falls due.
    public var fraction: Double { dueCount > 0 ? Double(paidCount) / Double(dueCount) : 0 }

    public init(bills: [BillReminder], in interval: DateInterval) {
        var due = 0, paid = 0
        var dueByCurrency: [String: Decimal] = [:], paidByCurrency: [String: Decimal] = [:]
        for bill in bills {
            for index in Self.occurrences(of: bill, in: interval) {
                due += 1
                dueByCurrency[bill.currencyCode, default: 0] += bill.amount
                if index < bill.nextIndex {
                    paid += 1
                    paidByCurrency[bill.currencyCode, default: 0] += bill.amount
                }
            }
        }
        dueCount = due
        paidCount = paid
        let single = dueByCurrency.count == 1 ? dueByCurrency.keys.first : nil
        currencyCode = single
        dueAmount = single.flatMap { dueByCurrency[$0] }
        paidAmount = single.map { paidByCurrency[$0] ?? 0 }
    }

    /// The indexes of `bill`'s occurrences dated inside `interval`.
    static func occurrences(of bill: BillReminder, in interval: DateInterval) -> [Int] {
        guard let recurrence = bill.recurrence else {
            return interval.contains(bill.dueDate) && bill.dueDate < interval.end ? [0] : []
        }
        var result: [Int] = []
        var index = 0
        while let date = recurrence.date(start: bill.dueDate, index: index), date < interval.end {
            if date >= interval.start { result.append(index) }
            index += 1
        }
        return result
    }
}

@MainActor
public protocol BillReminderRepository: AnyObject {
    func fetchBillReminders() async throws -> [BillReminder]
    func saveBillReminder(_ bill: BillReminder) async throws
    func deleteBillReminder(id: UUID) async throws
    func markBillPaid(id: UUID, occurrenceIndex: Int, createRecord: Bool, paidAt: Date) async throws
}

public struct WalletNotification: Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let date: Date?
    public init(id: String, title: String, body: String, date: Date? = nil) {
        self.id = id; self.title = title; self.body = body; self.date = date
    }
}

@MainActor
/// Schedules local notices.
///
/// `managing` names the identifier prefixes the caller owns. Synchronizing replaces the caller's
/// own pending notices and leaves every other source alone, so planning alerts and insight alerts
/// cannot cancel each other.
public protocol WalletNotificationClient: AnyObject {
    func requestAuthorization() async throws -> Bool
    /// Whether notices can already be delivered, so the app need not ask again.
    func isAuthorized() async -> Bool
    func synchronize(_ notifications: [WalletNotification], managing prefixes: [String]) async throws
}

public extension WalletNotificationClient {
    /// Planning's own notices: bills and budget thresholds.
    static var planningPrefixes: [String] { ["wallet.bill.", "wallet.budget."] }
    /// Weekly summaries, unusual spending, streaks and month comparisons.
    static var insightPrefixes: [String] { ["wallet.insight."] }
    /// Reminders for outstanding debts.
    static var debtPrefixes: [String] { ["wallet.debt."] }
}
