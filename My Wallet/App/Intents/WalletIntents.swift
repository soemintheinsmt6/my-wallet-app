import AppIntents
import Foundation
import WalletDomain

/// Adds an expense without opening the app.
///
/// Writes through `RecordUseCases`, so a record created by Siri gets exactly the same validation
/// and balance handling as one typed into the editor.
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Expense" }
    static var description: IntentDescription {
        IntentDescription("Records an expense in My Wallet.", categoryName: "Records")
    }
    /// Nothing needs to be shown, so this stays a background action.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Amount", controlStyle: .field, inclusiveRange: (0, 1_000_000_000))
    var amount: Double

    @Parameter(title: "Account")
    var account: AccountEntity?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Payee")
    var payee: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add a \(\.$amount) expense to \(\.$account)") {
            \.$category
            \.$payee
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repository = try await IntentWallet.open()
        let accounts = try await AccountUseCases(repository: repository).load()
        guard !accounts.isEmpty else { throw IntentError.noAccounts }

        // With no account given, fall back to the only one rather than asking pointlessly.
        let resolved: Account
        if let account, let match = accounts.first(where: { $0.id == account.id }) {
            resolved = match
        } else if accounts.count == 1 {
            resolved = accounts[0]
        } else {
            throw $account.needsValueError("Which account should this expense come from?")
        }

        guard let value = Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { throw IntentError.invalidAmount }

        var draft = RecordDraft()
        draft.kind = .expense
        draft.accountID = resolved.id
        draft.amount = CurrencyConverter.rounded(value, currencyCode: resolved.currencyCode)
        draft.categoryID = category?.id
        draft.payee = payee?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        draft.date = Date()

        try await RecordUseCases(repository: repository).create(id: UUID(), draft: draft)

        let formatted = draft.amount.formatted(.currency(code: resolved.currencyCode))
        return .result(dialog: "Added \(formatted) to \(resolved.name).")
    }
}

/// Reads a balance straight from the widget snapshot, so it answers without opening the store.
struct ShowBalanceIntent: AppIntent {
    static var title: LocalizedStringResource { "Show Balance" }
    static var description: IntentDescription {
        IntentDescription("Reports your total balance in My Wallet.", categoryName: "Summary")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Account")
    var account: AccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show the balance of \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // A specific account needs live figures; the overall total is in the snapshot already.
        if let account {
            let accounts = try await IntentWallet.accounts()
            guard let match = accounts.first(where: { $0.id == account.id }) else {
                throw IntentError.unknownAccount(account.name)
            }
            let formatted = match.settings.currentBalance.formatted(.currency(code: match.currencyCode))
            return .result(dialog: "\(match.name) has \(formatted).")
        }

        guard let snapshot = IntentWallet.snapshot(), let primary = snapshot.primaryBalance else {
            throw IntentError.noData
        }
        let formatted = primary.total.formatted(.currency(code: primary.currencyCode))
        guard snapshot.balances.count > 1 else {
            return .result(dialog: "Your total balance is \(formatted).")
        }
        let others = snapshot.balances
            .filter { $0.currencyCode != primary.currencyCode }
            .map { $0.total.formatted(.currency(code: $0.currencyCode)) }
            .joined(separator: ", ")
        return .result(dialog: "Your total balance is \(formatted), plus \(others).")
    }
}

/// Summarizes the current month from the widget snapshot.
struct MonthlySummaryIntent: AppIntent {
    static var title: LocalizedStringResource { "Monthly Summary" }
    static var description: IntentDescription {
        IntentDescription("Reports this month's income, expenses and net in My Wallet.",
                          categoryName: "Summary")
    }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let month = IntentWallet.snapshot()?.month else { throw IntentError.noData }
        let income = month.income.formatted(.currency(code: month.currencyCode))
        let expenses = month.expenses.formatted(.currency(code: month.currencyCode))
        let net = abs(month.net).formatted(.currency(code: month.currencyCode))
        let direction = month.net >= 0 ? "ahead by" : "behind by"
        let name = month.start.formatted(.dateTime.month(.wide))
        return .result(dialog: "In \(name) you earned \(income) and spent \(expenses) — \(direction) \(net).")
    }
}

/// Registers the phrases Siri accepts and the actions the Shortcuts app offers.
///
/// `applicationName` keeps every phrase anchored to the app, which Siri requires.
struct WalletShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense to \(.applicationName)",
                "Record a purchase in \(.applicationName)",
                "New expense in \(.applicationName)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle")

        AppShortcut(
            intent: ShowBalanceIntent(),
            phrases: [
                "What's my balance in \(.applicationName)",
                "Show my \(.applicationName) balance",
            ],
            shortTitle: "Show Balance",
            // A literal is required here; `wallet.bifold` would draw nothing before iOS 18.
            systemImageName: "wallet.pass")

        AppShortcut(
            intent: MonthlySummaryIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "\(.applicationName) monthly summary",
            ],
            shortTitle: "Monthly Summary",
            systemImageName: "chart.pie")
    }
}
