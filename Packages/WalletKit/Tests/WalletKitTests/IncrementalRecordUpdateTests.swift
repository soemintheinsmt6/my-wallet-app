import Foundation
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

/// A save, edit or delete updates the records and balances already in memory instead of reading
/// every record back, and the result must match what a full reload would show.
@MainActor
struct IncrementalRecordUpdateTests {
    private let base = Date(timeIntervalSince1970: 1_704_110_400) // 2024-01-01 12:00 UTC

    private func record(_ id: UUID = UUID(), account: UUID, amount: Decimal = 10, hoursAgo: Double = 0,
                        kind: RecordKind = .expense, destination: UUID? = nil, received: Decimal? = nil) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = account
        draft.destinationAccountID = destination
        draft.receivedAmount = received
        draft.amount = amount
        draft.date = base.addingTimeInterval(-hoursAgo * 3600)
        return WalletRecord(id: id, draft: draft, currencyCode: "USD")
    }

    // MARK: - Applying a change

    @Test func savedRecordsLandInDateOrderAndAMovedRecordIsReordered() throws {
        let account = UUID()
        let newest = record(account: account, hoursAgo: 1)
        let oldest = record(account: account, hoursAgo: 10)
        var list = [newest, oldest]

        let middle = record(account: account, hoursAgo: 5)
        list = try #require(RecordChangeApplier.records(list, applying: .saved(middle, previous: nil, version: 1)))
        #expect(list.map(\.id) == [newest.id, middle.id, oldest.id])

        // Editing the date moves it rather than leaving it where it was.
        let moved = record(middle.id, account: account, hoursAgo: 20)
        list = try #require(RecordChangeApplier.records(list, applying: .saved(moved, previous: middle, version: 2)))
        #expect(list.map(\.id) == [newest.id, oldest.id, middle.id])

        list = try #require(RecordChangeApplier.records(list, applying: .deleted(newest.id, previous: newest, version: 3)))
        #expect(list.map(\.id) == [oldest.id, middle.id])
        #expect(RecordChangeApplier.records(list, applying: .unknown) == nil)
    }

    /// The records list applies its own save at once and again when the notice arrives.
    @Test func applyingTheSameChangeTwiceChangesNothingTheSecondTime() throws {
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        let spent = record(account: cash.id, amount: 30)
        let change = RecordChange.saved(spent, previous: nil, version: 1)

        let once = try #require(RecordChangeApplier.records([], applying: change))
        let onceDrafts = try #require(RecordChangeApplier.drafts(in: [], for: change))
        let onceAccounts = RecordChangeApplier.accounts([cash], movingFrom: onceDrafts.before, to: onceDrafts.after)
        #expect(onceAccounts.first?.settings.currentBalance == 70)

        let twice = try #require(RecordChangeApplier.records(once, applying: change))
        let twiceDrafts = try #require(RecordChangeApplier.drafts(in: once, for: change))
        #expect(twice == once)
        #expect(RecordChangeApplier.accounts(onceAccounts, movingFrom: twiceDrafts.before, to: twiceDrafts.after) == onceAccounts)
    }

    @Test func balancesMoveByTheDifferenceIncludingTransfersBetweenAccounts() {
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        let bank = Account(name: "Bank", type: .checking, settings: AccountSettings(currentBalance: 50))
        let id = UUID()
        let expense = record(id, account: cash.id, amount: 30).draft
        let transfer = record(id, account: cash.id, amount: 40, kind: .transfer, destination: bank.id, received: 40).draft

        // An expense of 30 edited into a transfer of 40 to the bank.
        let moved = RecordChangeApplier.accounts([cash, bank], movingFrom: expense, to: transfer)
        #expect(moved.map(\.settings.currentBalance) == [90, 90])
        // Deleting the transfer returns both.
        let restored = RecordChangeApplier.accounts(moved, movingFrom: transfer, to: nil)
        #expect(restored.map(\.settings.currentBalance) == [130, 50])
    }

    // MARK: - Records view model

    @Test func savesEditsAndDeletesUpdateRecordsAndBalancesWithoutReadingTheLedgerAgain() async throws {
        let (repository, records, accounts) = try await counted()
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        let bank = Account(name: "Bank", type: .checking, settings: AccountSettings(currentBalance: 50))
        try await repository.createAccount(cash)
        try await repository.createAccount(bank)
        let category = try #require(try await repository.fetchCategories().first)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: records), accounts: AccountUseCases(repository: accounts),
                                         categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        await viewModel.reload()
        let recordLoads = records.loads
        let accountLoads = accounts.loads

        let id = UUID()
        var draft = RecordDraft()
        draft.accountID = cash.id
        draft.categoryID = category.id
        draft.amount = 30
        draft.note = "  Lunch  "
        try await viewModel.save(id: id, draft: draft)
        // As stored: the note trimmed and the currency resolved from the account.
        #expect(viewModel.records.first?.draft.note == "Lunch")
        #expect(viewModel.records.first?.currencyCode == "USD")
        try await expectBalances(viewModel.accounts, match: repository)

        draft.kind = .transfer
        draft.destinationAccountID = bank.id
        draft.amount = 40
        try await viewModel.save(id: id, draft: draft, editing: true)
        #expect(viewModel.records.count == 1)
        try await expectBalances(viewModel.accounts, match: repository)

        try await viewModel.delete(id: id)
        #expect(viewModel.records.isEmpty)
        try await expectBalances(viewModel.accounts, match: repository)

        await settle()
        #expect(records.loads == recordLoads)
        #expect(accounts.loads == accountLoads)
    }

    /// A record written elsewhere — the watch, Shortcuts, a debt payment — arrives as a notice.
    @Test func aRecordWrittenElsewhereIsAppliedFromItsNotice() async throws {
        let (repository, records, accounts) = try await counted()
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        try await repository.createAccount(cash)
        let category = try #require(try await repository.fetchCategories().first)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: records), accounts: AccountUseCases(repository: accounts),
                                         categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let observing = Task { await viewModel.observe() }
        await observing.value
        let recordLoads = records.loads

        var draft = RecordDraft()
        draft.accountID = cash.id
        draft.categoryID = category.id
        draft.amount = 12
        try await repository.createRecord(id: UUID(), draft: draft)

        try await waitUntil { viewModel.records.count == 1 }
        try await expectBalances(viewModel.accounts, match: repository)
        #expect(records.loads == recordLoads)
    }

    /// Anything wider than one record — here an account edit that records an adjustment — reloads.
    @Test func anUnknownChangeStillReloadsEverything() async throws {
        let (repository, records, accounts) = try await counted()
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        try await repository.createAccount(cash)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: records), accounts: AccountUseCases(repository: accounts),
                                         categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let observing = Task { await viewModel.observe() }
        await observing.value
        let recordLoads = records.loads

        try await repository.updateAccount(id: cash.id, name: "Cash", type: .cash,
                                           settings: AccountSettings(currentBalance: 120))
        try await waitUntil { records.loads > recordLoads }
        try await waitUntil { viewModel.accounts.first?.settings.currentBalance == 120 }
    }

    // MARK: - Accounts view model

    @Test func accountBalancesFollowRecordChangesWithoutSummingTheLedgerAgain() async throws {
        let (repository, _, accounts) = try await counted()
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        try await repository.createAccount(cash)
        let category = try #require(try await repository.fetchCategories().first)
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: accounts))
        let observing = Task { await viewModel.observe() }
        await observing.value
        let accountLoads = accounts.loads

        let id = UUID()
        var draft = RecordDraft()
        draft.accountID = cash.id
        draft.categoryID = category.id
        draft.amount = 30
        try await repository.createRecord(id: id, draft: draft)
        try await waitUntil { viewModel.accounts.first?.settings.currentBalance == 70 }

        draft.amount = 45
        try await repository.updateRecord(id: id, draft: draft)
        try await waitUntil { viewModel.accounts.first?.settings.currentBalance == 55 }

        try await repository.deleteRecord(id: id)
        try await waitUntil { viewModel.accounts.first?.settings.currentBalance == 100 }
        try await expectBalances(viewModel.accounts, match: repository)
        #expect(accounts.loads == accountLoads)
    }

    /// A reload that lands between a save and its notice already counts the save; the notice must
    /// not count it again.
    @Test func aReloadBetweenASaveAndItsNoticeDoesNotCountTheChangeTwice() async throws {
        let (repository, _, accounts) = try await counted()
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        try await repository.createAccount(cash)
        let category = try #require(try await repository.fetchCategories().first)
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: accounts))
        let observing = Task { await viewModel.observe() }
        await observing.value

        var draft = RecordDraft()
        draft.accountID = cash.id
        draft.categoryID = category.id
        draft.amount = 30
        for _ in 0..<5 {
            try await repository.createRecord(id: UUID(), draft: draft)
            // Read straight away, before or after the notice is handled.
            await viewModel.reload()
        }
        await settle()
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.accounts.first?.settings.currentBalance == -50)
        try await expectBalances(viewModel.accounts, match: repository)
    }

    /// Without ledger versions a screen cannot tell what a load includes, so it reloads instead.
    @Test func withoutLedgerVersionsAccountChangesReloadRatherThanGuess() async throws {
        let change = RecordChange.saved(record(account: UUID()), previous: nil, version: nil)
        #expect(change.version == nil)
        #expect(RecordChange.unknown.version == nil)
        #expect(RecordChange.deleted(UUID(), previous: nil, version: 7).version == 7)
    }

    /// The store's own saves post `NSPersistentStoreRemoteChange` too; those must not reload.
    @Test func theStoresOwnSavesDoNotTriggerAFullReload() async throws {
        let (repository, records, accounts) = try await counted()
        let cash = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        try await repository.createAccount(cash)
        let category = try #require(try await repository.fetchCategories().first)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: records), accounts: AccountUseCases(repository: accounts),
                                         categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let observing = Task { await viewModel.observe() }
        await observing.value
        // Let the notices from setting up the store pass first.
        try await Task.sleep(for: .milliseconds(200))
        let recordLoads = records.loads

        var draft = RecordDraft()
        draft.accountID = cash.id
        draft.categoryID = category.id
        draft.amount = 5
        try await viewModel.save(id: UUID(), draft: draft)
        // Long enough for the store's remote change notice and its history check to arrive.
        try await Task.sleep(for: .milliseconds(300))
        #expect(records.loads == recordLoads)
        #expect(viewModel.records.count == 1)
    }

    // MARK: - Helpers

    private func counted() async throws -> (SwiftDataWalletRepository, CountingRecordReads, CountingAccountReads) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        return (repository, CountingRecordReads(repository), CountingAccountReads(repository))
    }

    /// The in-memory balances must equal what the store sums from every record.
    private func expectBalances(_ accounts: [Account], match repository: SwiftDataWalletRepository) async throws {
        let stored = try await repository.fetchAccounts()
        #expect(accounts.map(\.id) == stored.map(\.id))
        #expect(accounts.map(\.settings.currentBalance) == stored.map(\.settings.currentBalance))
    }

    /// Lets queued change notices run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Condition was not met in time")
    }
}

/// Counts full record reads, passing everything else, including change notices, through.
@MainActor
private final class CountingRecordReads: RecordRepository {
    private let wrapped: SwiftDataWalletRepository
    private(set) var loads = 0
    init(_ wrapped: SwiftDataWalletRepository) { self.wrapped = wrapped }

    func fetchRecords() async throws -> [WalletRecord] {
        loads += 1
        return try await wrapped.fetchRecords()
    }
    func createRecord(id: UUID, draft: RecordDraft) async throws -> WalletRecord { try await wrapped.createRecord(id: id, draft: draft) }
    func updateRecord(id: UUID, draft: RecordDraft) async throws -> WalletRecord { try await wrapped.updateRecord(id: id, draft: draft) }
    func deleteRecord(id: UUID) async throws { try await wrapped.deleteRecord(id: id) }
    func recordPhoto(id: UUID) async throws -> Data? { try await wrapped.recordPhoto(id: id) }
    func changes() -> AsyncStream<Void> { wrapped.changes() }
    func recordChanges() -> AsyncStream<RecordChange> { wrapped.recordChanges() }
}

/// Counts account loads, each of which sums every record into balances.
@MainActor
private final class CountingAccountReads: AccountRepository {
    private let wrapped: SwiftDataWalletRepository
    private(set) var loads = 0
    init(_ wrapped: SwiftDataWalletRepository) { self.wrapped = wrapped }

    func fetchAccounts() async throws -> [Account] {
        loads += 1
        return try await wrapped.fetchAccounts()
    }
    func fetchAccountsWithLedgerVersion() async throws -> (accounts: [Account], ledgerVersion: Int?) {
        loads += 1
        return try await wrapped.fetchAccountsWithLedgerVersion()
    }
    func createAccount(_ account: Account) async throws { try await wrapped.createAccount(account) }
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        try await wrapped.updateAccount(id: id, name: name, type: type, settings: settings)
    }
    func accountDeletionImpact(id: UUID) async throws -> AccountDeletionImpact { try await wrapped.accountDeletionImpact(id: id) }
    func deleteAccount(id: UUID, strategy: AccountDeletionStrategy) async throws {
        try await wrapped.deleteAccount(id: id, strategy: strategy)
    }
    func changes() -> AsyncStream<Void> { wrapped.changes() }
    func recordChanges() -> AsyncStream<RecordChange> { wrapped.recordChanges() }
}
