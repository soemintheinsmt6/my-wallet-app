import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain
import WalletFeature

@MainActor
struct TagTests {
    @Test func createsAllColorsAndEditsWithoutChangingIdentity() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = TagUseCases(repository: repository)
        for color in TagColor.allCases {
            try await useCases.create(name: "  \(color.rawValue) \n", color: color)
        }
        let tags = try await useCases.load()
        #expect(tags.count == 10)
        #expect(Set(tags.map(\.color)) == Set(TagColor.allCases))
        #expect(tags.allSatisfy { $0.name == $0.color.rawValue })
        let first = try #require(tags.first)
        try await useCases.update(id: first.id, name: "  Work  ", color: .indigo)
        let edited = try #require(try await useCases.load().first { $0.id == first.id })
        #expect(edited.name == "Work")
        #expect(edited.color == .indigo)
        #expect(try await useCases.load().count == 10)
    }

    @Test func validatesNamesAndRejectsDuplicatesOnCreateAndEdit() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = TagUseCases(repository: repository)
        for name in ["", " \n ", String(repeating: "a", count: 81)] {
            await #expect(throws: TagValidationError.self) { try await useCases.create(name: name, color: .blue) }
        }
        try await useCases.create(name: "Café", color: .orange)
        await #expect(throws: TagValidationError.self) { try await useCases.create(name: " CAFE ", color: .red) }
        try await useCases.create(name: "Work", color: .blue)
        let work = try #require(try await useCases.load().first { $0.name == "Work" })
        await #expect(throws: TagValidationError.self) { try await useCases.update(id: work.id, name: "cafe", color: .green) }
        await #expect(throws: TagValidationError.self) { try await useCases.update(id: UUID(), name: "Missing", color: .green) }
        #expect(try await useCases.load().first { $0.id == work.id }?.name == "Work")
    }

    @Test func deletionRemovesOnlySelectedLabelAndNotifiesObservers() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let useCases = TagUseCases(repository: repository)
        try await useCases.create(name: "Work", color: .blue)
        try await useCases.create(name: "Vacation", color: .yellow)
        let work = try #require(try await useCases.load().first { $0.name == "Work" })
        let changes = repository.changes()
        try await useCases.delete(id: work.id)
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        #expect(try await useCases.load().map(\.name) == ["Vacation"])
        try await useCases.delete(id: work.id)
        #expect(try await useCases.load().count == 1)
    }

    @Test func viewModelReflectsCreateEditAndDelete() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let viewModel = TagsViewModel(useCases: TagUseCases(repository: repository))
        try await viewModel.save(name: "Work", color: .blue)
        let tag = try #require(viewModel.tags.first)
        try await viewModel.save(id: tag.id, name: "Business", color: .purple)
        #expect(viewModel.tags.first?.name == "Business")
        try await viewModel.delete(id: tag.id)
        #expect(viewModel.tags.isEmpty)
        #expect(!viewModel.isSaving)
        #expect(!viewModel.isLoading)
    }

    @Test func failuresPreserveLoadedLabelsAndReleaseSavingState() async {
        let repository = FailingTagRepository()
        let viewModel = TagsViewModel(useCases: TagUseCases(repository: repository))
        await viewModel.reload()
        await #expect(throws: FailingTagRepository.Failure.self) {
            try await viewModel.save(name: "New", color: .green)
        }
        await #expect(throws: FailingTagRepository.Failure.self) {
            try await viewModel.save(id: repository.tag.id, name: "Changed", color: .green)
        }
        await #expect(throws: FailingTagRepository.Failure.self) {
            try await viewModel.delete(id: repository.tag.id)
        }
        #expect(viewModel.tags == [repository.tag])
        #expect(!viewModel.isSaving)
    }

    @Test func tagSchemaPreservesExistingDataAndDeletionSurvivesReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let account = Account(name: "Cash", type: .cash)
        let category = WalletCategory(name: "Custom", nature: .want)

        func writePreviousSchema() throws {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(AccountRecord(account: account))
            context.insert(CategoryRecord(category: category))
            try context.save()
        }

        func openContainer() throws -> ModelContainer {
            let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self, TagRecord.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }

        func createLabel() async throws -> UUID {
            let container = try openContainer()
            let context = ModelContext(container)
            #expect(try context.fetch(FetchDescriptor<AccountRecord>()).map(\.account) == [account])
            #expect(try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.category) == [category])
            let store = WalletStore(modelContainer: container)
            try await store.createTag(name: "Work", color: .indigo)
            return try #require(try await store.fetchTags().first?.id)
        }

        func reopenAndDelete(id: UUID) async throws {
            let container = try openContainer()
            let store = WalletStore(modelContainer: container)
            #expect(try await store.fetchTags() == [WalletTag(id: id, name: "Work", color: .indigo)])
            try await store.deleteTag(id: id)
        }

        try writePreviousSchema()
        let id = try await createLabel()
        try await reopenAndDelete(id: id)
        let container = try openContainer()
        #expect(try ModelContext(container).fetch(FetchDescriptor<TagRecord>()).isEmpty)
    }
}

@MainActor
private final class FailingTagRepository: TagRepository {
    struct Failure: Error {}
    let tag = WalletTag(name: "Work")
    func fetchTags() async throws -> [WalletTag] { [tag] }
    func createTag(name: String, color: TagColor) async throws { throw Failure() }
    func updateTag(id: UUID, name: String, color: TagColor) async throws { throw Failure() }
    func deleteTag(id: UUID) async throws { throw Failure() }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
