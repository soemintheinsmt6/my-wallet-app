import Combine
import Foundation
import WalletDomain

@MainActor
public final class RecordsViewModel: ObservableObject {
    @Published public private(set) var records: [WalletRecord] = []
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var categories: [WalletCategory] = []
    @Published public private(set) var tags: [WalletTag] = []
    @Published public private(set) var isLoading = true
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: RecordUseCases
    private let accountUseCases: AccountUseCases
    private let categoryUseCases: CategoryUseCases
    private let tagUseCases: TagUseCases
    private var generation = 0

    public init(useCases: RecordUseCases, accounts: AccountUseCases, categories: CategoryUseCases, tags: TagUseCases) {
        self.useCases = useCases
        accountUseCases = accounts
        categoryUseCases = categories
        tagUseCases = tags
    }

    public func observe() async {
        let changes = useCases.changes()
        await reload()
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await reload()
        }
    }

    public func reload() async {
        generation += 1
        let version = generation
        isLoading = true
        defer { if generation == version { isLoading = false } }
        do {
            let accounts = try await accountUseCases.load()
            let categories = try await categoryUseCases.load()
            let tags = try await tagUseCases.load()
            let records = try await useCases.load()
            try Task.checkCancellation()
            guard version == generation else { return }
            self.accounts = accounts
            self.categories = categories
            self.tags = tags
            self.records = records
        } catch is CancellationError {
        } catch { if version == generation { errorMessage = error.localizedDescription } }
    }

    public func save(id: UUID, draft: RecordDraft, editing: Bool = false) async throws {
        guard !isSaving else { throw RecordValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        if editing { try await useCases.update(id: id, draft: draft) }
        else { try await useCases.create(id: id, draft: draft) }
        await reload()
    }

    public func delete(id: UUID) async throws {
        guard !isSaving else { throw RecordValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.delete(id: id)
        await reload()
    }

    public func photo(id: UUID) async throws -> Data? { try await useCases.photo(id: id) }
    func account(_ id: UUID?) -> Account? { accounts.first { $0.id == id } }
    func category(_ id: UUID?) -> WalletCategory? { categories.first { $0.id == id } }
    func categoryTitle(_ id: UUID?) -> String {
        guard let category = category(id) else { return "Uncategorized" }
        if let parent = self.category(category.parentID) { return "\(parent.name) / \(category.name)" }
        return category.name
    }

    public func mostUsedCategories(for kind: RecordKind) -> [WalletCategory] {
        let matching = records.filter { $0.draft.kind == kind }
        let counts = Dictionary(grouping: matching.compactMap { $0.draft.categoryID }, by: { $0 }).mapValues(\.count)
        let recent = Dictionary(grouping: matching.filter { $0.draft.categoryID != nil }, by: { $0.draft.categoryID! })
            .mapValues { $0.map(\.draft.date).max() ?? .distantPast }
        return Array(categories.filter { counts[$0.id] != nil }.sorted {
            if counts[$0.id] != counts[$1.id] { return counts[$0.id, default: 0] > counts[$1.id, default: 0] }
            if recent[$0.id] != recent[$1.id] { return recent[$0.id, default: .distantPast] > recent[$1.id, default: .distantPast] }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(6))
    }
}
