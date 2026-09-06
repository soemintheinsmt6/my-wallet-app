import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature
#if os(macOS)
import AppKit
#endif

@MainActor
struct CategoryTests {
    @Test func categoryDefaultsUseRelevantNaturesAndValidIcons() {
        let roots = CategorySeeds.categories.filter { $0.parentID == nil }
        #expect(roots.map(\.nature) == [.need, .want, .must, .need, .need, .want, .need, .must, .need, .none])
        #expect(roots.map(\.symbol) == ["fork.knife", "bag", "house", "bus", "car", "theatermasks", "laptopcomputer", "banknote", "chart.line.uptrend.xyaxis", "arrow.down.circle"])
        #expect(CategorySeeds.categories.first { $0.name == "Groceries" }?.nature == .need)
        #expect(CategorySeeds.categories.first { $0.name == "Restaurant" }?.nature == .want)
        #expect(CategorySeeds.categories.first { $0.name == "Taxes" }?.nature == .must)
        for category in CategorySeeds.categories {
            #expect(category.symbol != "tag")
            #if os(macOS)
            #expect(NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil) != nil)
            #endif
        }
    }

    @Test func upgradesUntouchedSeedNaturesButPreservesExplicitUserChoices() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        let food = try #require(CategorySeeds.categories.first { $0.name == "Food & Drinks" })
        let housing = try #require(CategorySeeds.categories.first { $0.name == "Housing" })
        context.insert(CategoryRecord(category: WalletCategory(id: food.id, name: food.name), updatedAt: Date(timeIntervalSince1970: 0)))
        context.insert(CategoryRecord(category: WalletCategory(id: housing.id, name: "My Home", nature: .none), updatedAt: Date(timeIntervalSince1970: 100)))
        let store = WalletStore(modelContainer: container)
        try context.save()
        let categories = try await store.fetchCategories()
        #expect(categories.first { $0.id == food.id }?.nature == .need)
        #expect(categories.first { $0.id == housing.id }?.nature == CategoryNature.none)
        #expect(categories.first { $0.id == housing.id }?.name == "My Home")
        #expect(categories.first { $0.id == housing.id }?.symbol == "house")
        #expect(try await store.fetchCategories() == categories)
    }

    @Test func seedsTenCategoriesAndFiftySubcategoriesOnlyOnce() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let first = try await repository.fetchCategories()
        let second = try await repository.fetchCategories()
        #expect(first == second)
        #expect(first.filter { $0.parentID == nil }.map(\.name) == [
            "Food & Drinks", "Shopping", "Housing", "Transportation", "Vehicle",
            "Life & Entertainment", "Communication (PC)", "Financial Expenses", "Investments", "Income",
        ])
        #expect(first.filter { $0.parentID != nil }.count == 50)
        #expect(Set(first.map(\.id)).count == 60)
        #expect(first.allSatisfy { category in CategorySeeds.categories.first { $0.id == category.id }?.nature == category.nature })
        let food = try #require(first.first { $0.name == "Food & Drinks" })
        #expect(first.filter { $0.parentID == food.id }.map(\.name) == ["Groceries", "Restaurant", "Fast Food", "Bar & Café"])
    }

    @Test func editsToSeedsSurviveReloadAndKeepIndependentNatures() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = CategoryUseCases(repository: repository)
        let initial = try await useCases.load()
        let food = try #require(initial.first { $0.name == "Food & Drinks" })
        let groceries = try #require(initial.first { $0.name == "Groceries" })
        try await useCases.update(id: food.id, name: "  Meals  ", nature: .need)
        try await useCases.update(id: groceries.id, name: "Weekly Shop", nature: .must)
        let reloaded = try await useCases.load()
        #expect(reloaded.count == initial.count)
        #expect(reloaded.first { $0.id == food.id }?.name == "Meals")
        #expect(reloaded.first { $0.id == food.id }?.nature == .need)
        #expect(reloaded.first { $0.id == groceries.id }?.nature == .must)
        #expect(reloaded.first { $0.id == groceries.id }?.parentID == food.id)
        #expect(reloaded.filter { $0.parentID == food.id && $0.id != groceries.id }.allSatisfy { child in
            initial.first { $0.id == child.id }?.nature == child.nature
        })
    }

    @Test func createsCustomHierarchyAndRejectsDuplicateSiblingNames() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = CategoryUseCases(repository: repository)
        try await useCases.create(name: "  Pets  ", nature: .want)
        let parent = try #require(try await useCases.load().first { $0.name == "Pets" })
        try await useCases.create(name: "Food", nature: .must, parentID: parent.id)
        await #expect(throws: CategoryValidationError.self) {
            try await useCases.create(name: "  food  ", nature: .none, parentID: parent.id)
        }
        await #expect(throws: CategoryValidationError.self) {
            try await useCases.create(name: "pets", nature: .none)
        }
        // The same subcategory name is valid under a different parent.
        let shopping = try #require(try await useCases.load().first { $0.name == "Shopping" })
        try await useCases.create(name: "Food", nature: .need, parentID: shopping.id)
        let children = try await useCases.load().filter { $0.parentID == parent.id }
        #expect(children.count == 1)
        #expect(children.first?.nature == .must)
        await #expect(throws: CategoryValidationError.self) {
            try await useCases.update(id: parent.id, name: "Shopping", nature: .none)
        }
    }

    @Test func rejectsInvalidNamesMissingParentsAndThirdLevelNesting() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = CategoryUseCases(repository: repository)
        for name in ["", " \n ", String(repeating: "a", count: 81)] {
            await #expect(throws: CategoryValidationError.self) {
                try await useCases.create(name: name, nature: .none)
            }
        }
        let categories = try await useCases.load()
        let child = try #require(categories.first { $0.parentID != nil })
        for parent in [UUID(), child.id] {
            await #expect(throws: CategoryValidationError.self) {
                try await useCases.create(name: "Invalid Child", nature: .none, parentID: parent)
            }
        }
        await #expect(throws: CategoryValidationError.self) {
            try await useCases.update(id: UUID(), name: "Missing", nature: .need)
        }
        #expect(try await useCases.load().count == 60)
    }

    @Test func duplicateSeedReplicasPreferUserEditAndRemainOneVisibleCategory() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        let seed = try #require(CategorySeeds.categories.first)
        context.insert(CategoryRecord(category: seed, updatedAt: Date(timeIntervalSince1970: 0)))
        let edited = WalletCategory(id: seed.id, name: "Edited Food", nature: .want, sortOrder: seed.sortOrder)
        context.insert(CategoryRecord(category: edited, updatedAt: Date(timeIntervalSince1970: 100)))
        try context.save()
        let store = WalletStore(modelContainer: container)
        let categories = try await store.fetchCategories()
        #expect(categories.count == 60)
        #expect(categories.first { $0.id == seed.id } == edited)
        try await store.updateCategory(id: seed.id, name: "Meals", nature: .need)
        let records = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>()).filter { $0.id == seed.id }
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.name == "Meals" && $0.natureValue == "need" })
    }

    @Test func viewModelPublishesNewAndEditedCategories() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let viewModel = CategoriesViewModel(useCases: CategoryUseCases(repository: repository))
        await viewModel.reload()
        try await viewModel.save(name: "Pets", nature: .want)
        let parent = try #require(viewModel.rootCategories.first { $0.name == "Pets" })
        try await viewModel.save(parentID: parent.id, name: "Vet", nature: .must)
        let child = try #require(viewModel.subcategories(of: parent.id).first)
        try await viewModel.save(id: child.id, name: "Veterinary Care", nature: .need)
        #expect(viewModel.category(id: child.id)?.name == "Veterinary Care")
        #expect(!viewModel.isSaving)
        #expect(!viewModel.isLoading)
    }

    @Test func failedDeletionReleasesCategorySavingState() async throws {
        let viewModel = CategoriesViewModel(useCases: CategoryUseCases(repository: FailingCategoryRepository()))
        await #expect(throws: FailingCategoryRepository.Failure.self) {
            try await viewModel.delete(id: UUID(), strategy: .deleteSubcategories)
        }
        #expect(!viewModel.isSaving)
    }

    @Test func failedSaveRestoresViewModelStateAndReportsLoadFailure() async {
        let viewModel = CategoriesViewModel(useCases: CategoryUseCases(repository: FailingCategoryRepository()))
        await viewModel.reload()
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.isLoading)
        await #expect(throws: FailingCategoryRepository.Failure.self) {
            try await viewModel.save(name: "Pets", nature: .none)
        }
        #expect(!viewModel.isSaving)
        #expect(viewModel.categories.isEmpty)
    }

    @Test func categorySchemaPreservesAccountsAndEditsSurviveReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let account = Account(name: "Cash", type: .cash, currencyCode: "MMK")

        func writePreviousSchema() throws {
            let schema = Schema([Item.self, AccountRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(AccountRecord(account: account))
            try context.save()
        }

        func openCurrentContainer() throws -> ModelContainer {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }

        func seedAndEdit() async throws -> UUID {
            let container = try openCurrentContainer()
            #expect(try ModelContext(container).fetch(FetchDescriptor<AccountRecord>()).map(\.account) == [account])
            let store = WalletStore(modelContainer: container)
            let category = try #require(try await store.fetchCategories().first { $0.parentID == nil })
            try await store.updateCategory(id: category.id, name: "Renamed", nature: .must)
            return category.id
        }

        try writePreviousSchema()
        let id = try await seedAndEdit()
        let container = try openCurrentContainer()
        let store = WalletStore(modelContainer: container)
        let categories = try await store.fetchCategories()
        #expect(categories.count == 60)
        #expect(categories.first { $0.id == id }?.name == "Renamed")
        #expect(categories.first { $0.id == id }?.nature == .must)
    }
}

@MainActor
private final class FailingCategoryRepository: CategoryRepository {
    func deleteCategory(id: UUID, strategy: CategoryDeletionStrategy) async throws { throw Failure() }
    struct Failure: Error {}
    func fetchCategories() async throws -> [WalletCategory] { throw Failure() }
    func createCategory(name: String, nature: CategoryNature, parentID: UUID?) async throws { throw Failure() }
    func updateCategory(id: UUID, name: String, nature: CategoryNature) async throws { throw Failure() }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
