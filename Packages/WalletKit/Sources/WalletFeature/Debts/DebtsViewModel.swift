import Combine
import Foundation
import WalletDomain

/// Debts and savings goals, both of which sit alongside the ledger rather than inside it.
///
/// Settling a debt or contributing to a goal can optionally write a real record, so the money
/// movement shows up in balances and statistics; the link is kept so the two stay consistent.
@MainActor
public final class DebtsViewModel: ObservableObject {
    @Published public private(set) var debts: [DebtProgress] = []
    @Published public private(set) var goals: [GoalProgress] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?

    public let records: RecordsViewModel
    private let debtUseCases: DebtUseCases
    private let goalUseCases: GoalUseCases
    private let recordUseCases: RecordUseCases
    private let notifications: (any WalletNotificationClient)?

    public init(repository: any DebtRepository & GoalRepository & RecordRepository,
                records: RecordsViewModel, notifications: (any WalletNotificationClient)? = nil) {
        debtUseCases = DebtUseCases(repository: repository)
        goalUseCases = GoalUseCases(repository: repository)
        recordUseCases = RecordUseCases(repository: repository)
        self.records = records
        self.notifications = notifications
    }

    public var balances: [PersonBalance] { DebtUseCases.balances(debts) }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            debts = try await debtUseCases.load()
            goals = try await goalUseCases.load()
            try await synchronizeNotifications()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Debts

    public func save(_ debt: Debt) async throws {
        try await mutate { try await debtUseCases.save(debt) }
    }

    public func deleteDebt(id: UUID) async throws {
        try await mutate { try await debtUseCases.delete(id: id) }
    }

    /// Records a payment, optionally writing a matching ledger record.
    ///
    /// The record is written first: if it fails the payment is not recorded either, so the two
    /// never disagree about what happened.
    public func pay(_ progress: DebtProgress, amount: Decimal, account: Account?,
                    categoryID: UUID?) async throws {
        try await mutate {
            var recordID: UUID?
            if let account {
                var draft = RecordDraft()
                draft.kind = progress.debt.direction.settlementKind
                draft.accountID = account.id
                draft.categoryID = categoryID
                draft.amount = amount
                draft.date = Date()
                draft.payee = progress.debt.person
                draft.note = "Debt settlement"
                let id = UUID()
                try await recordUseCases.create(id: id, draft: draft)
                recordID = id
            }
            try await debtUseCases.pay(progress, amount: amount, recordID: recordID)
            await records.reload()
        }
    }

    public func deletePayment(id: UUID) async throws {
        try await mutate { try await debtUseCases.deletePayment(id: id) }
    }

    // MARK: - Goals

    public func save(_ goal: SavingsGoal) async throws {
        try await mutate { try await goalUseCases.save(goal) }
    }

    public func deleteGoal(id: UUID) async throws {
        try await mutate { try await goalUseCases.delete(id: id) }
    }

    /// Adds to or withdraws from a goal, optionally moving real money as a transfer.
    public func contribute(to goal: SavingsGoal, amount: Decimal, from account: Account?,
                           to destination: Account?, categoryID: UUID?) async throws {
        try await mutate {
            var recordID: UUID?
            if let account, let destination, account.id != destination.id, amount > 0 {
                var draft = RecordDraft()
                draft.kind = .transfer
                draft.accountID = account.id
                draft.destinationAccountID = destination.id
                draft.categoryID = categoryID
                draft.amount = amount
                draft.date = Date()
                draft.note = "Contribution to \(goal.name)"
                let id = UUID()
                try await recordUseCases.create(id: id, draft: draft)
                recordID = id
            }
            try await goalUseCases.contribute(to: goal, amount: amount, recordID: recordID)
            await records.reload()
        }
    }

    public func deleteContribution(id: UUID) async throws {
        try await mutate { try await goalUseCases.deleteContribution(id: id) }
    }

    // MARK: - Plumbing

    private func mutate(_ operation: () async throws -> Void) async throws {
        guard !isSaving else { throw DebtError.busy }
        isSaving = true
        defer { isSaving = false }
        try await operation()
        await refresh()
    }

    public func requestNotifications() async {
        do {
            guard let notifications, try await notifications.requestAuthorization() else {
                errorMessage = "Notifications are disabled. Enable them for My Wallet in system settings."
                return
            }
            try await synchronizeNotifications()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Reminders for debts that are still outstanding and have a due date.
    private func synchronizeNotifications() async throws {
        guard let notifications else { return }
        let notices = debts.compactMap { progress -> WalletNotification? in
            guard progress.debt.notificationsEnabled, !progress.isSettled,
                  let due = progress.debt.dueDate else { return nil }
            let amount = progress.outstanding.formatted(.currency(code: progress.debt.currencyCode))
            let title = progress.debt.direction == .owedToMe
                ? "\(progress.debt.person) owes you \(amount)"
                : "You owe \(progress.debt.person) \(amount)"
            return WalletNotification(
                id: "wallet.debt.\(progress.debt.id).\(Int(due.timeIntervalSince1970))",
                title: title,
                body: "Due \(due.formatted(date: .abbreviated, time: .omitted)).",
                date: due > Date() ? due : nil)
        }
        try await notifications.synchronize(notices, managing: type(of: notifications).debtPrefixes)
    }
}
