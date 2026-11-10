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
