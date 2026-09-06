import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

@MainActor
struct AccountTests {
    @Test func editsPersistAllSettingsAndPreserveCurrencyAndIdentity() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = AccountUseCases(repository: repository)
        try await useCases.create(name: "Cash", type: .cash, currencyCode: "MMK")
        let original = try #require(try await useCases.load().first)
        let settings = AccountSettings(currentBalance: Decimal(string: "-123.45678901")!, color: .purple, notifyBelowMinimum: true, minimumBalance: 0, notifyAboveMaximum: true, maximumBalance: 1000, excludeFromStats: true)
        try await useCases.update(id: original.id, name: "  Credit  ", type: .creditCard, settings: settings)
        let updated = try #require(try await useCases.load().first)
        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.currencyCode == "MMK")
        #expect(updated.name == "Credit")
        #expect(updated.type == .creditCard)
        #expect(updated.settings == settings)
        #expect(try await useCases.load().count == 1)
    }

    @Test func balanceAlertsUseStrictLimitsAndExclusionDoesNotDisableThem() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: repository))
        var settings = AccountSettings(currentBalance: 5, notifyBelowMinimum: true, minimumBalance: 10, notifyAboveMaximum: true, maximumBalance: 20, excludeFromStats: true)
        try await viewModel.create(name: "Cash", type: .cash, settings: settings)
        let id = try #require(viewModel.accounts.first?.id)
        #expect(viewModel.balanceNotifications.count == 1)
        #expect(viewModel.accountsIncludedInStats.isEmpty)
        for balance in [10, 15, 20] {
            settings.currentBalance = Decimal(balance)
            try await viewModel.update(id: id, name: "Cash", type: .cash, settings: settings)
            #expect(viewModel.balanceNotifications.isEmpty)
        }
        settings.currentBalance = 21
        settings.excludeFromStats = false
        try await viewModel.update(id: id, name: "Cash", type: .cash, settings: settings)
        #expect(viewModel.balanceNotifications.count == 1)
        #expect(viewModel.accountsIncludedInStats.count == 1)
        settings.notifyAboveMaximum = false
        try await viewModel.update(id: id, name: "Cash", type: .cash, settings: settings)
        #expect(viewModel.balanceNotifications.isEmpty)
    }

    @Test func invalidCurrencyAmountsAndLimitsDoNotSave() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = AccountUseCases(repository: repository)
        await #expect(throws: AccountValidationError.self) {
            try await useCases.create(name: "Cash", type: .cash, currencyCode: "INVALID")
        }
        for settings in [
            AccountSettings(currentBalance: .nan),
            AccountSettings(currentBalance: Decimal(string: "0.000000001")!),
            AccountSettings(notifyBelowMinimum: true, minimumBalance: 20, notifyAboveMaximum: true, maximumBalance: 10),
        ] {
            await #expect(throws: AccountValidationError.self) {
                try await useCases.create(name: "Cash", type: .cash, settings: settings)
            }
        }
        #expect(try await useCases.load().isEmpty)
        await #expect(throws: AccountValidationError.self) {
            try await useCases.update(id: UUID(), name: "Missing", type: .other, settings: AccountSettings())
        }
    }

    @Test func amountInputParsesWholeLocalizedValueWithoutRounding() throws {
        #expect(try AccountAmountInput.parse("-123,45678901", locale: Locale(identifier: "de_DE")) == Decimal(string: "-123.45678901"))
        for text in ["12abc", "1,000", "", "NaN", "1e3", "0.123456789"] {
            #expect(throws: AccountValidationError.self) {
                try AccountAmountInput.parse(text, locale: Locale(identifier: "en_US"))
            }
        }
    }

    @Test func failedDeletionPreservesAccountsAndReleasesSavingState() async throws {
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: FailingAccountRepository()))
        await viewModel.reload()
        await #expect(throws: FailingAccountRepository.Failure.self) {
            try await viewModel.delete(id: UUID(), strategy: .keepRecords)
        }
        #expect(!viewModel.isSaving)
        #expect(viewModel.accounts.isEmpty)
    }

    @Test func failedUpdateRestoresSavingState() async {
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: FailingAccountRepository()))
        await #expect(throws: FailingAccountRepository.Failure.self) {
            try await viewModel.update(id: UUID(), name: "Cash", type: .cash, settings: AccountSettings())
        }
        #expect(!viewModel.isSaving)
    }

    @Test func addingAccountSchemaPreservesExistingEntriesAndAccountsSurviveReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let entry = WalletEntry()
        let account = Account(name: "Savings", type: .savings, currencyCode: "EUR", settings: AccountSettings(currentBalance: Decimal(string: "123.45")!, color: .green, notifyBelowMinimum: true, minimumBalance: 500, notifyAboveMaximum: true, maximumBalance: 1000, excludeFromStats: true))

        func writePreviousSchema() throws {
            let schema = Schema([Item.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(Item(entry: entry))
            try context.save()
        }

        func openCurrentStore() throws -> ModelContainer {
            let schema = Schema([Item.self, AccountRecord.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }

        func writeAccount() throws {
            let container = try openCurrentStore()
            let context = ModelContext(container)
            #expect(try context.fetch(FetchDescriptor<Item>()).map(\.entry) == [entry])
            context.insert(AccountRecord(account: account))
            try context.save()
        }

        try writePreviousSchema()
        try writeAccount()
        let container = try openCurrentStore()
        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<AccountRecord>()).map(\.account) == [account])
    }

    @Test func savesEveryAccountTypeAndTrimsNames() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = AccountUseCases(repository: repository)
        for type in AccountType.allCases {
            try await useCases.create(name: "  My \(type.rawValue)  \n", type: type)
        }
        let accounts = try await repository.fetchAccounts()
        #expect(accounts.count == 7)
        #expect(Set(accounts.map(\.type)) == Set(AccountType.allCases))
        #expect(Set(accounts.map(\.id)).count == 7)
        #expect(accounts.allSatisfy { $0.name == "My \($0.type.rawValue)" })
    }

    @Test func invalidNamesAreNotPersisted() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = AccountUseCases(repository: repository)
        for name in ["", "  \n", String(repeating: "a", count: 81)] {
            await #expect(throws: AccountValidationError.self) {
                try await useCases.create(name: name, type: .cash)
            }
        }
        #expect(try await repository.fetchAccounts().isEmpty)
        try await useCases.create(name: String(repeating: "a", count: 80), type: .other)
        #expect(try await repository.fetchAccounts().count == 1)
    }

    @Test func creationUpdatesAccountList() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: repository))
        try await viewModel.create(name: "Everyday Cash", type: .cash)
        #expect(viewModel.accounts.map(\.name) == ["Everyday Cash"])
        #expect(!viewModel.isSaving)
        #expect(!viewModel.isLoading)
    }

    @Test func failedSaveThrowsAndRestoresFormState() async {
        let viewModel = AccountsViewModel(useCases: AccountUseCases(repository: FailingAccountRepository()))
        await #expect(throws: FailingAccountRepository.Failure.self) {
            try await viewModel.create(name: "Main Checking", type: .checking)
        }
        #expect(!viewModel.isSaving)
        #expect(viewModel.accounts.isEmpty)
    }
}

@MainActor
private final class FailingAccountRepository: AccountRepository {
    func accountDeletionImpact(id: UUID) async throws -> AccountDeletionImpact { throw Failure() }
    func deleteAccount(id: UUID, strategy: AccountDeletionStrategy) async throws { throw Failure() }
    struct Failure: Error {}
    func fetchAccounts() async throws -> [Account] { [] }
    func createAccount(_ account: Account) async throws { throw Failure() }
    func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws { throw Failure() }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
