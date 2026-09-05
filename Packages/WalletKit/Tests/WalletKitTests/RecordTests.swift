import Foundation
import SwiftData
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import WalletData
import WalletDomain
@testable import WalletFeature

@MainActor
struct RecordTests {
    private func setup() async throws -> (SwiftDataWalletRepository, Account, Account, WalletCategory) {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let source = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        let destination = Account(name: "Bank", type: .checking)
        try await repository.createAccount(source)
        try await repository.createAccount(destination)
        let category = try #require(try await repository.fetchCategories().first)
        return (repository, source, destination, category)
    }

    private func draft(_ account: Account, _ category: WalletCategory?, kind: RecordKind = .expense, amount: Decimal = 10) -> RecordDraft {
        var value = RecordDraft()
        value.accountID = account.id
        value.categoryID = category?.id
        value.kind = kind
        value.amount = amount
        return value
    }

    @Test func ledgerUpdatesBalancesAndRetriedSubmissionDoesNotDoubleCount() async throws {
        let (repository, source, destination, category) = try await setup()
        let useCases = RecordUseCases(repository: repository)
        try await useCases.create(id: UUID(), draft: draft(source, category, amount: Decimal(string: "12.34")!))
        try await useCases.create(id: UUID(), draft: draft(source, category, kind: .income, amount: 5))
        var transfer = draft(source, nil, kind: .transfer, amount: 20)
        transfer.destinationAccountID = destination.id
        transfer.receivedAmount = 99 // Same-currency transfers always credit exactly the sent amount.
        let id = UUID()
        try await useCases.create(id: id, draft: transfer)
        try await useCases.create(id: id, draft: transfer)
        let accounts = try await repository.fetchAccounts()
        #expect(accounts.first { $0.id == source.id }?.settings.currentBalance == Decimal(string: "72.66"))
        #expect(accounts.first { $0.id == destination.id }?.settings.currentBalance == 20)
        #expect(try await useCases.load().count == 3)
        let saved = try #require(try await useCases.load().first { $0.id == id })
        #expect(saved.draft.receivedAmount == 20)
        var adjusted = source.settings
        adjusted.currentBalance = 200
        try await repository.updateAccount(id: source.id, name: source.name, type: source.type, settings: adjusted)
        #expect(try await repository.fetchAccounts().first { $0.id == source.id }?.settings.currentBalance == 200)
    }

    @Test func crossCurrencyTransferRequiresExplicitReceivedAmount() async throws {
        let (repository, source, _, _) = try await setup()
        let foreign = Account(name: "Euro", type: .cash, currencyCode: "EUR")
        try await repository.createAccount(foreign)
        var transfer = draft(source, nil, kind: .transfer, amount: 10)
        transfer.destinationAccountID = foreign.id
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: transfer) }
        #expect(try await repository.fetchRecords().isEmpty)
        transfer.receivedAmount = Decimal(string: "8.75")!
        try await repository.createRecord(id: UUID(), draft: transfer)
        let accounts = try await repository.fetchAccounts()
        #expect(accounts.first { $0.id == source.id }?.settings.currentBalance == 90)
        #expect(accounts.first { $0.id == foreign.id }?.settings.currentBalance == Decimal(string: "8.75"))
        #expect(try await repository.fetchRecords().first?.destinationCurrencyCode == "EUR")
    }

    @Test func rejectsInvalidAmountsTransfersAndReferencesWithoutChangingBalances() async throws {
        let (repository, source, _, category) = try await setup()
        var invalid = draft(source, category)
        for amount in [Decimal(0), Decimal(-1), Decimal.nan, Decimal(string: "0.000000001")!] {
            invalid.amount = amount
            await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: invalid) }
        }
        invalid = draft(source, nil)
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: invalid) }
        invalid = draft(source, category, kind: .transfer)
        invalid.destinationAccountID = source.id
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: invalid) }
        invalid = draft(source, category)
        invalid.tagIDs = [UUID()]
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: invalid) }
        invalid = draft(source, category)
        invalid.categoryID = UUID()
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: invalid) }
        invalid = draft(source, category)
        invalid.accountID = UUID()
        await #expect(throws: RecordValidationError.self) { try await repository.createRecord(id: UUID(), draft: invalid) }
        #expect(try await repository.fetchRecords().isEmpty)
        #expect(try await repository.fetchAccounts().first { $0.id == source.id }?.settings.currentBalance == 100)
    }

    @Test func savesDetailsAndDeletingLabelKeepsRecordAndBalance() async throws {
        let (repository, source, _, category) = try await setup()
        try await repository.createTag(name: "Work", color: .indigo)
        let label = try #require(try await repository.fetchTags().first)
        var values = draft(source, category)
        values.tagIDs = [label.id]
        values.date = Date(timeIntervalSince1970: 1_000_000)
        values.note = "  Lunch meeting  "
        values.payee = "  Café  "
        values.paymentType = .creditCard
        values.photoData = try samplePhoto()
        let id = UUID()
        try await repository.createRecord(id: id, draft: values)
        let saved = try #require(try await repository.fetchRecords().first)
        #expect(saved.draft.note == "Lunch meeting")
        #expect(saved.draft.payee == "Café")
        #expect(saved.draft.paymentType == .creditCard)
        #expect(saved.draft.date == values.date)
        #expect(saved.draft.tagIDs == [label.id])
        #expect(saved.hasPhoto)
        #expect(saved.draft.photoData == nil)
        #expect(try await repository.recordPhoto(id: id) == values.photoData)
        try await repository.deleteTag(id: label.id)
        #expect(try await repository.fetchRecords().count == 1)
        #expect(try await repository.fetchRecords().first?.draft.tagIDs.isEmpty == true)
        #expect(try await repository.fetchAccounts().first { $0.id == source.id }?.settings.currentBalance == 90)
    }

    @Test func mostUsedRanksExactCategoriesPerKindAndUpdatesAfterSaving() async throws {
        let (repository, source, _, root) = try await setup()
        let child = try #require(try await repository.fetchCategories().first { $0.parentID == root.id })
        let viewModel = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: AccountUseCases(repository: repository), categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        await viewModel.reload()
        #expect(viewModel.mostUsedCategories(for: .expense).isEmpty)
        try await viewModel.save(id: UUID(), draft: draft(source, root))
        try await viewModel.save(id: UUID(), draft: draft(source, child))
        try await viewModel.save(id: UUID(), draft: draft(source, child))
        try await viewModel.save(id: UUID(), draft: draft(source, root, kind: .income))
        #expect(viewModel.mostUsedCategories(for: .expense).map(\.id) == [child.id, root.id])
        #expect(viewModel.mostUsedCategories(for: .income).map(\.id) == [root.id])
        #expect(viewModel.mostUsedCategories(for: .transfer).isEmpty)
        #expect(!viewModel.isSaving)
        #expect(viewModel.records.count == 4)
    }

    @Test func validatesTextAndAttachmentLimitsAndProcessesImage() throws {
        var values = RecordDraft()
        values.accountID = UUID()
        values.categoryID = UUID()
        values.amount = 1
        values.note = String(repeating: "a", count: 2001)
        #expect(throws: RecordValidationError.self) { try values.validate() }
        values.note = ""
        values.photoData = Data(count: 5 * 1024 * 1024 + 1)
        #expect(throws: RecordValidationError.self) { try values.validate() }
        #expect(throws: RecordValidationError.self) { try RecordPhoto.prepare(Data([1, 2, 3])) }
        let photo = try samplePhoto()
        #expect(photo.count < 5 * 1024 * 1024)
        let source = try #require(CGImageSourceCreateWithData(photo as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func migrationKeepsOldDataAndRecordBalancesAndPhotosSurviveReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let account = Account(name: "Cash", type: .cash, settings: AccountSettings(currentBalance: 100))
        let category = WalletCategory(name: "Food")
        let photo = try samplePhoto()
        let id = UUID()

        func seedPreviousSchema() throws {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self, TagRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(AccountRecord(account: account))
            context.insert(CategoryRecord(category: category))
            try context.save()
        }
        func openContainer() throws -> ModelContainer {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self, TagRecord.self, TransactionRecord.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        func save() async throws {
            let container = try openContainer()
            let store = WalletStore(modelContainer: container)
            #expect(try await store.fetchAccounts() == [account])
            var values = draft(account, category, amount: 25)
            values.photoData = photo
            try await store.createRecord(id: id, draft: values)
        }
        try seedPreviousSchema()
        try await save()
        let container = try openContainer()
        let store = WalletStore(modelContainer: container)
        #expect(try await store.fetchRecords().count == 1)
        #expect(try await store.fetchAccounts().first?.settings.currentBalance == 75)
        #expect(try await store.recordPhoto(id: id) == photo)
    }

    private func samplePhoto() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return try RecordPhoto.prepare(output as Data)
    }
}
