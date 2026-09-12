import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

@MainActor
struct CoreLifecycleTests {
    private func setup() async throws -> (SwiftDataWalletRepository, Account, Account, WalletCategory) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let a = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        let b = Account(name: "Euro", type: .checking, currencyCode: "EUR", settings: AccountSettings(currentBalance: 50))
        try await repository.createAccount(a)
        try await repository.createAccount(b)
        let category = try #require(try await repository.fetchCategories().first { $0.parentID == nil })
        return (repository, a, b, category)
    }

    private func draft(_ account: Account, _ category: WalletCategory, kind: RecordKind = .expense) -> RecordDraft {
        var draft = RecordDraft()
        draft.accountID = account.id
        draft.categoryID = category.id
        draft.kind = kind
        draft.amount = 20
        return draft
    }

    @Test func editingReversesOldAccountAndKindAndNormalizesTransferAmounts() async throws {
        let (repository, a, b, category) = try await setup()
        let useCases = RecordUseCases(repository: repository)
        let id = UUID()
        var value = draft(a, category)
        try await useCases.create(id: id, draft: value)
        value.accountID = b.id
        value.kind = .income
        value.amount = 35
        try await useCases.update(id: id, draft: value)
        var accounts = try await repository.fetchAccounts()
        #expect(accounts.first { $0.id == a.id }?.settings.currentBalance == 100)
        #expect(accounts.first { $0.id == b.id }?.settings.currentBalance == 85)
        value.kind = .transfer
        value.accountID = a.id
        value.destinationAccountID = b.id
        value.amount = 10
        value.receivedAmount = 9
        try await useCases.update(id: id, draft: value)
        accounts = try await repository.fetchAccounts()
        #expect(accounts.first { $0.id == a.id }?.settings.currentBalance == 90)
        #expect(accounts.first { $0.id == b.id }?.settings.currentBalance == 59)
        value.accountID = b.id
        value.destinationAccountID = a.id
        value.receivedAmount = 11
        try await useCases.update(id: id, draft: value)
        accounts = try await repository.fetchAccounts()
        #expect(accounts.first { $0.id == a.id }?.settings.currentBalance == 111)
        #expect(accounts.first { $0.id == b.id }?.settings.currentBalance == 40)
        value.kind = .expense
        try await useCases.update(id: id, draft: value)
        let saved = try #require(try await useCases.load().first)
        #expect(saved.id == id)
        #expect(saved.currencyCode == "EUR")
        #expect(saved.draft.destinationAccountID == nil)
        #expect(saved.destinationCurrencyCode == nil)
        #expect(saved.draft.receivedAmount == nil)
        #expect(try await repository.fetchAccounts().first { $0.id == a.id }?.settings.currentBalance == 100)
    }

    /// The dashboard, the record list and the statistics screen share one records view model. Each
    /// used to start its own change loop and reload on activation, so a single change cost three
    /// concurrent loads — and three `isLoading` flips, which read on screen as the spinner
    /// flashing several times.
    @Test func screensSharingTheRecordsModelLoadItOnceBetweenThem() async throws {
        let (repository, _, _, _) = try await setup()
        let counting = CountingRecords(wrapping: repository)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: counting),
                                         accounts: AccountUseCases(repository: repository),
                                         categories: CategoryUseCases(repository: repository),
                                         tags: TagUseCases(repository: repository))

        // Three screens appearing at once.
        let screens = (0..<3).map { _ in Task { await viewModel.observe() } }
        for screen in screens { await screen.value }
        // One load for the first caller, and one more pass covering the two that arrived while it
        // ran, rather than three loads racing each other.
        #expect(counting.loads == 2)
        #expect(!viewModel.isLoading)

        // And one change reaches one loop, not three.
        let before = counting.loads
        counting.announceChange()
        try await Task.sleep(for: .milliseconds(50))
        #expect(counting.loads == before + 1)
    }

    @Test func editingSameCurrencyTransferUsesSentAmountAndPublishesUpdatedBalances() async throws {
        let (repository, a, _, category) = try await setup()
        let b = Account(name: "Second USD", type: .cash)
        try await repository.createAccount(b)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: AccountUseCases(repository: repository),
                                         categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let id = UUID()
        try await viewModel.save(id: id, draft: draft(a, category))
        var edited = draft(a, category, kind: .transfer)
        edited.destinationAccountID = b.id
        edited.receivedAmount = 99
        edited.amount = 25
        try await viewModel.save(id: id, draft: edited, editing: true)
        #expect(viewModel.records.count == 1)
        #expect(viewModel.records.first?.draft.receivedAmount == 25)
        #expect(viewModel.accounts.first { $0.id == a.id }?.settings.currentBalance == 75)
        #expect(viewModel.accounts.first { $0.id == b.id }?.settings.currentBalance == 25)
        try await viewModel.delete(id: id)
        #expect(viewModel.records.isEmpty)
        #expect(viewModel.accounts.first { $0.id == a.id }?.settings.currentBalance == 100)
    }

    @Test func failedEditPreservesRecordPhotoAndBothBalancesAndDoesNotRecreateMissingRecord() async throws {
        let (repository, a, b, category) = try await setup()
        let id = UUID()
        var value = draft(a, category, kind: .transfer)
        value.destinationAccountID = b.id
        value.receivedAmount = 18
        value.photoData = Data([1, 2, 3])
        try await repository.createRecord(id: id, draft: value)
        let original = try await repository.fetchRecords()
        let balances = try await repository.fetchAccounts()
        value.destinationAccountID = UUID()
        await #expect(throws: RecordValidationError.self) { try await repository.updateRecord(id: id, draft: value) }
        #expect(try await repository.fetchRecords() == original)
        #expect(try await repository.fetchAccounts() == balances)
        #expect(try await repository.recordPhoto(id: id) == Data([1, 2, 3]))
        value.destinationAccountID = b.id
        await #expect(throws: RecordValidationError.self) { try await repository.updateRecord(id: UUID(), draft: value) }
        #expect(try await repository.fetchRecords().count == 1)
    }

    @Test func editsEveryDetailAndReplacesThenRemovesPhoto() async throws {
        let (repository, a, _, category) = try await setup()
        let id = UUID()
        var value = draft(a, category)
        value.photoData = Data([1])
        try await repository.createRecord(id: id, draft: value)
        try await repository.createTag(name: "Edited", color: .blue)
        let tag = try #require(try await repository.fetchTags().first)
        let other = try #require(try await repository.fetchCategories().first { $0.id != category.id })
        value.categoryID = other.id
        value.note = "  New note  "
        value.payee = "New payee"
        value.tagIDs = [tag.id]
        value.paymentType = .bankTransfer
        value.date = Date(timeIntervalSince1970: 1234)
        value.photoData = Data([2, 3])
        try await repository.updateRecord(id: id, draft: value)
        let saved = try #require(try await repository.fetchRecords().first)
        #expect(saved.draft.categoryID == other.id)
        #expect(saved.draft.note == "New note")
        #expect(saved.draft.payee == value.payee)
        #expect(saved.draft.tagIDs == value.tagIDs)
        #expect(saved.draft.paymentType == value.paymentType)
        #expect(saved.draft.date == value.date)
        #expect(saved.hasPhoto)
        #expect(try await repository.recordPhoto(id: id) == Data([2, 3]))
        value.photoData = nil
        try await repository.updateRecord(id: id, draft: value)
        #expect(try await repository.fetchRecords().first?.hasPhoto == false)
        #expect(try await repository.recordPhoto(id: id) == nil)
    }

    @Test(arguments: RecordKind.allCases)
    func deletingEachKindRestoresBalancesAndRemovesPhoto(kind: RecordKind) async throws {
        let (repository, a, b, category) = try await setup()
        let id = UUID()
        var value = draft(a, category, kind: kind)
        if kind == .transfer { value.destinationAccountID = b.id; value.receivedAmount = 18 }
        value.photoData = Data([1])
        try await repository.createRecord(id: id, draft: value)
        let stream = repository.changes()
        var changes = stream.makeAsyncIterator()
        try await RecordUseCases(repository: repository).delete(id: id)
        #expect(await changes.next() != nil)
        try await RecordUseCases(repository: repository).delete(id: id)
        #expect(try await repository.fetchRecords().isEmpty)
        #expect(try await repository.recordPhoto(id: id) == nil)
        let accounts = try await repository.fetchAccounts()
        #expect(accounts.first { $0.id == a.id }?.settings.currentBalance == 100)
        #expect(accounts.first { $0.id == b.id }?.settings.currentBalance == 50)
    }

    @Test(arguments: [AccountDeletionStrategy.keepRecords, .deleteRecords], [true, false])
    func accountDeletionHandlesEitherTransferSide(strategy: AccountDeletionStrategy, deletingSource: Bool) async throws {
        let (repository, a, b, category) = try await setup()
        let id = UUID()
        var value = draft(a, category, kind: .transfer)
        value.destinationAccountID = b.id
        value.receivedAmount = 18
        value.photoData = Data([1])
        try await repository.createRecord(id: id, draft: value)
        let deleting = deletingSource ? a : b
        let impact = try await AccountUseCases(repository: repository).deletionImpact(id: deleting.id)
        #expect(impact.recordCount == 1)
        #expect(impact.transferCount == 1)
        #expect(impact.account.settings.currentBalance == (deletingSource ? 80 : 68))
        try await AccountUseCases(repository: repository).delete(id: deleting.id, strategy: strategy)
        let remaining = try #require(try await repository.fetchAccounts().first)
        #expect(remaining.id == (deletingSource ? b.id : a.id))
        if strategy == .deleteRecords {
            #expect(remaining.settings.currentBalance == (deletingSource ? 50 : 100))
            #expect(try await repository.fetchRecords().isEmpty)
            #expect(try await repository.recordPhoto(id: id) == nil)
        } else {
            #expect(remaining.settings.currentBalance == (deletingSource ? 68 : 80))
            let saved = try #require(try await repository.fetchRecords().first)
            #expect(deletingSource ? saved.draft.accountID == nil : saved.draft.destinationAccountID == nil)
            #expect(try await repository.recordPhoto(id: id) == Data([1]))
            try await repository.deleteRecord(id: id)
            #expect(try await repository.fetchAccounts().first?.settings.currentBalance == (deletingSource ? 50 : 100))
        }
    }

    @Test func categoryCascadeUncategorizesRecordsAndDoesNotReseedDeletedDefaults() async throws {
        let (repository, a, _, root) = try await setup()
        let child = try #require(try await repository.fetchCategories().first { $0.parentID == root.id })
        let id = UUID()
        try await repository.createRecord(id: id, draft: draft(a, child))
        try await repository.deleteCategory(id: root.id, strategy: .deleteSubcategories)
        for _ in 0..<2 {
            let categories = try await repository.fetchCategories()
            #expect(!categories.contains { $0.id == root.id || $0.parentID == root.id })
        }
        let record = try #require(try await repository.fetchRecords().first)
        #expect(record.draft.categoryID == nil)
        #expect(try await repository.fetchAccounts().first { $0.id == a.id }?.settings.currentBalance == 80)
        var edited = record.draft
        edited.note = "Still editable"
        try await RecordUseCases(repository: repository).update(id: id, draft: edited)
        #expect(try await repository.fetchRecords().first?.draft.note == "Still editable")
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: draft(a, child)) }
    }

    @Test func reassigningChildrenPreservesTheirRecordReferencesAndRejectsDuplicateNames() async throws {
        let (repository, a, _, root) = try await setup()
        let child = try #require(try await repository.fetchCategories().first { $0.parentID == root.id })
        try await repository.createCategory(name: "Destination", nature: .none, parentID: nil)
        let destination = try #require(try await repository.fetchCategories().first { $0.name == "Destination" })
        try await repository.createCategory(name: child.name, nature: .none, parentID: destination.id)
        await #expect(throws: CategoryValidationError.self) {
            try await repository.deleteCategory(id: root.id, strategy: .reassignSubcategories(to: destination.id))
        }
        #expect(try await repository.fetchCategories().contains { $0.id == root.id })
        let duplicate = try #require(try await repository.fetchCategories().first { $0.parentID == destination.id })
        try await repository.deleteCategory(id: duplicate.id, strategy: .deleteSubcategories)
        let id = UUID()
        try await repository.createRecord(id: id, draft: draft(a, child))
        try await repository.deleteCategory(id: root.id, strategy: .reassignSubcategories(to: destination.id))
        #expect(try await repository.fetchCategories().first { $0.id == child.id }?.parentID == destination.id)
        #expect(try await repository.fetchRecords().first?.draft.categoryID == child.id)
    }

    @Test func cannotDeleteLastCategoryOrItsWholeTree() async throws {
        let (repository, _, _, _) = try await setup()
        let roots = try await repository.fetchCategories().filter { $0.parentID == nil }
        for root in roots.dropLast() { try await repository.deleteCategory(id: root.id, strategy: .deleteSubcategories) }
        let last = try #require(roots.last)
        await #expect(throws: CategoryValidationError.self) { try await repository.deleteCategory(id: last.id, strategy: .deleteSubcategories) }
        #expect(try await repository.fetchCategories().contains { $0.id == last.id })
    }

    @Test func failedRecordMutationsPreservePublishedDataAndReleaseSavingState() async throws {
        let (repository, a, _, category) = try await setup()
        let record = WalletRecord(id: UUID(), draft: draft(a, category), currencyCode: "USD")
        let failing = FailingRecordMutations(record: record)
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: failing), accounts: AccountUseCases(repository: repository),
                                         categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        await viewModel.reload()
        await #expect(throws: FailingRecordMutations.Failure.self) {
            try await viewModel.save(id: record.id, draft: record.draft, editing: true)
        }
        #expect(viewModel.records == [record])
        #expect(!viewModel.isSaving)
        await #expect(throws: FailingRecordMutations.Failure.self) { try await viewModel.delete(id: record.id) }
        #expect(viewModel.records == [record])
        #expect(!viewModel.isSaving)
    }
}

/// Counts the loads a view model actually performs, passing everything else through.
@MainActor
private final class CountingRecords: RecordRepository {
    private let wrapped: any RecordRepository
    private(set) var loads = 0
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(wrapping wrapped: any RecordRepository) {
        self.wrapped = wrapped
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func announceChange() { continuation.yield() }

    func fetchRecords() async throws -> [WalletRecord] {
        loads += 1
        return try await wrapped.fetchRecords()
    }

    func createRecord(id: UUID, draft: RecordDraft) async throws { try await wrapped.createRecord(id: id, draft: draft) }
    func updateRecord(id: UUID, draft: RecordDraft) async throws { try await wrapped.updateRecord(id: id, draft: draft) }
    func deleteRecord(id: UUID) async throws { try await wrapped.deleteRecord(id: id) }
    func recordPhoto(id: UUID) async throws -> Data? { try await wrapped.recordPhoto(id: id) }
    func changes() -> AsyncStream<Void> { stream }
}

@MainActor
private final class FailingRecordMutations: RecordRepository {
    struct Failure: Error {}
    let record: WalletRecord
    init(record: WalletRecord) { self.record = record }
    func fetchRecords() async throws -> [WalletRecord] { [record] }
    func createRecord(id: UUID, draft: RecordDraft) async throws { throw Failure() }
    func updateRecord(id: UUID, draft: RecordDraft) async throws { throw Failure() }
    func deleteRecord(id: UUID) async throws { throw Failure() }
    func recordPhoto(id: UUID) async throws -> Data? { throw Failure() }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
