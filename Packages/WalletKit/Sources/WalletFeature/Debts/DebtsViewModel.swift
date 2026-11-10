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
    /// Whether system notifications are already allowed, so the request button can be hidden.
    /// Starts true so the button does not flash before the first check in the usual case.
    @Published public private(set) var notificationsAuthorized = true

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
            publishLoanTitles()
            try await synchronizeNotifications()
        } catch { errorMessage = error.localizedDescription }
    }

    /// The record title for each balance adjustment a debt's money recorded: lending or borrowing it,
    /// and each repayment. Only for debts whose money moved; the income and expenses other debts
    /// settle with keep their category, as any income or expense does.
    nonisolated static func loanTitles(_ debts: [DebtProgress]) -> [UUID: String] {
        var titles: [UUID: String] = [:]
        for progress in debts where progress.debt.movedMoney {
            let person = progress.debt.person
            let lent = progress.debt.direction == .owedToMe
            if let id = progress.debt.openingRecordID {
                titles[id] = lent ? "Lent to \(person)" : "Borrowed from \(person)"
            }
            for payment in progress.payments {
                if let id = payment.recordID { titles[id] = lent ? "Repaid by \(person)" : "Repaid to \(person)" }
            }
        }
        return titles
    }

    private func publishLoanTitles() {
        let titles = Self.loanTitles(debts)
        if records.loanTitles != titles { records.loanTitles = titles }
    }

    // MARK: - Debts

    /// Saves a debt. With `account`, for a debt whose money has not been recorded yet, also records
    /// the money changing hands as a balance adjustment on that account (out when lending, in when
    /// borrowing), dated when the debt was made. An adjustment moves the balance without counting as
    /// income or spending, which a loan is not.
    ///
    /// The debt is checked before the adjustment is written, and the adjustment is removed again if
    /// the debt then fails to save, so neither is left without the other. A debt whose adjustment
    /// already exists keeps it in step with its person, direction and amount.
    public func save(_ debt: Debt, moneyMovedThrough account: Account? = nil) async throws {
        try await mutate {
            var value = debt
            var writtenID: UUID?
            if let id = debt.openingRecordID {
                try await syncOpeningRecord(id: id, with: debt)
            } else if let account {
                var checked = debt
                checked.person = debt.person.trimmingCharacters(in: .whitespacesAndNewlines)
                try checked.validate()
                let id = UUID()
                try await recordUseCases.create(id: id, draft: openingDraft(for: checked, account: account))
                writtenID = id
                value.openingRecordID = id
            }
            do {
                try await debtUseCases.save(value)
            } catch {
                if let writtenID { try? await recordUseCases.delete(id: writtenID) }
                throw error
            }
            if value.openingRecordID != nil { await records.reload() }
        }
    }

    private func openingDraft(for debt: Debt, account: Account) -> RecordDraft {
        var draft = RecordDraft.adjustment(accountID: account.id, increase: debt.direction.openingIncreasesBalance,
                                           amount: debt.amount, date: debt.createdAt)
        draft.payee = debt.person
        draft.note = debt.direction == .owedToMe ? "Lent to \(debt.person)" : "Borrowed from \(debt.person)"
        return draft
    }

    /// Keeps the opening adjustment matching an edited debt: its amount, which way it moved and who
    /// it was with. Everything else, including any note or label added to that record since, stays.
    /// If the person deleted that record themselves, there is nothing to keep in step.
    private func syncOpeningRecord(id: UUID, with debt: Debt) async throws {
        guard let record = records.records.first(where: { $0.id == id }) else { return }
        var draft = record.draft
        draft.amount = debt.amount
        draft.kind = debt.direction.openingIncreasesBalance ? .income : .expense
        draft.payee = debt.person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft != record.draft else { return }
        // A loaded record leaves its photo out, and an update writes the draft's photo as given, so
        // a photo attached to this record is read back first rather than erased.
        if record.hasPhoto { draft.photoData = try await recordUseCases.photo(id: id) }
        _ = try await recordUseCases.update(id: id, draft: draft)
    }

    public func deleteDebt(id: UUID) async throws {
        try await mutate { try await debtUseCases.delete(id: id) }
    }

    /// Records a payment, optionally writing a matching ledger record.
    ///
    /// For a debt whose money was recorded moving when it was made, the record is a balance
    /// adjustment the other way, so lending and being repaid leave the balance where it started and
    /// count as neither income nor spending. Otherwise it is income or an expense.
    ///
    /// The record is written first: if it fails the payment is not recorded either, so the two
    /// never disagree about what happened.
    public func pay(_ progress: DebtProgress, amount: Decimal, account: Account?,
                    categoryID: UUID?) async throws {
        try await mutate {
            var recordID: UUID?
            if let account {
                let debt = progress.debt
                var draft: RecordDraft
                if debt.movedMoney {
                    draft = .adjustment(accountID: account.id, increase: !debt.direction.openingIncreasesBalance,
                                        amount: amount)
                    draft.note = debt.direction == .owedToMe ? "Repaid by \(debt.person)" : "Repaid to \(debt.person)"
                } else {
                    draft = RecordDraft()
                    draft.kind = debt.direction.settlementKind
                    draft.accountID = account.id
                    draft.categoryID = categoryID
                    draft.amount = amount
                    draft.date = Date()
                    draft.note = "Debt settlement"
                }
                draft.payee = debt.person
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
                notificationsAuthorized = false
                errorMessage = "Notifications are disabled. Enable them for My Wallet in system settings."
                return
            }
            notificationsAuthorized = true
            try await synchronizeNotifications()
        } catch { errorMessage = error.localizedDescription }
    }

    public func refreshNotificationAuthorization() async {
        guard let notifications else { return }
        notificationsAuthorized = await notifications.isAuthorized()
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
