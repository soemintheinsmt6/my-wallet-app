import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain

private enum BeforeCategoryDeletion {
    @Model final class CategoryRecord {
        var id: UUID = UUID()
        var parentID: UUID?
        var name: String = ""
        var natureValue: String = "none"
        var sortOrder: Int = 0
        var updatedAt: Date = Date(timeIntervalSince1970: 0)
        var replicaID: UUID = UUID()
        init(id: UUID) { self.id = id; name = "Existing category" }
    }
}

@MainActor
struct CategoryDeletionMigrationTests {
    @Test func olderSeedReplicaDoesNotRestoreDeletedCategoryOrAcceptNewAssignments() async throws {
        let container = try WalletPersistence.makeContainer(configuration: .inMemory)
        let store = WalletStore(modelContainer: container)
        let category = try #require(try await store.fetchCategories().first { $0.parentID == nil })
        try await store.deleteCategory(id: category.id, strategy: .deleteSubcategories)
        let context = ModelContext(container)
        context.insert(CategoryRecord(category: category, updatedAt: Date(timeIntervalSince1970: 0)))
        try context.save()
        #expect(try await store.fetchCategories().allSatisfy { $0.id != category.id })
        let account = Account(name: "Cash", type: .cash)
        try await store.createAccount(account)
        var draft = RecordDraft()
        draft.accountID = account.id
        draft.categoryID = category.id
        draft.amount = 1
        await #expect(throws: RecordValidationError.self) { try await store.createRecord(id: UUID(), draft: draft) }
    }

    @Test func oldCategoriesRemainVisibleAndDeletedSeedsStayDeletedAfterReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let id = UUID()
        func seedOldSchema() throws {
            let schema = Schema([BeforeCategoryDeletion.CategoryRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(BeforeCategoryDeletion.CategoryRecord(id: id))
            try context.save()
        }
        func open() throws -> ModelContainer {
            let schema = Schema([CategoryRecord.self, TransactionRecord.self, AccountRecord.self, TagRecord.self, Item.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        func migrateAndDelete() async throws -> UUID {
            let container = try open()
            let existing = try #require(try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>()).first)
            #expect(existing.id == id)
            #expect(existing.deletionDate == nil)
            #expect(existing.name == "Existing category")
            let store = WalletStore(modelContainer: container)
            let seed = try #require(try await store.fetchCategories().first { $0.id != id && $0.parentID == nil })
            try await store.deleteCategory(id: seed.id, strategy: .deleteSubcategories)
            return seed.id
        }
        try seedOldSchema()
        let deletedID = try await migrateAndDelete()
        let store = WalletStore(modelContainer: try open())
        let categories = try await store.fetchCategories()
        #expect(categories.contains { $0.id == id })
        #expect(!categories.contains { $0.id == deletedID || $0.parentID == deletedID })
    }
}
