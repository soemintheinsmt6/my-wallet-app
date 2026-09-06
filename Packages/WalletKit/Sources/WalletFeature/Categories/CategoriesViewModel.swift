import Combine
import Foundation
import WalletDomain

@MainActor
public final class CategoriesViewModel: ObservableObject {
    @Published public private(set) var categories: [WalletCategory] = []
    @Published public private(set) var isLoading = true
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: CategoryUseCases
    private var loadVersion = 0

    public init(useCases: CategoryUseCases) { self.useCases = useCases }

    public var rootCategories: [WalletCategory] { categories.filter { $0.parentID == nil } }
    public func subcategories(of id: UUID) -> [WalletCategory] { categories.filter { $0.parentID == id } }
    public func category(id: UUID) -> WalletCategory? { categories.first { $0.id == id } }

    public func observe() async {
        let changes = useCases.changes()
        await reload()
        for await _ in changes {
            guard !Task.isCancelled else { break }
            await reload()
        }
    }

    public func reload() async {
        loadVersion += 1
        let version = loadVersion
        isLoading = true
        defer { if version == loadVersion { isLoading = false } }
        do {
            let loaded = try await useCases.load()
            try Task.checkCancellation()
            guard version == loadVersion else { return }
            categories = loaded
        } catch is CancellationError {
        } catch {
            if version == loadVersion { errorMessage = error.localizedDescription }
        }
    }

    public func delete(id: UUID, strategy: CategoryDeletionStrategy) async throws {
        guard !isSaving else { throw CategoryValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.delete(id: id, strategy: strategy)
        await reload()
    }

    public func save(id: UUID? = nil, parentID: UUID? = nil, name: String, nature: CategoryNature) async throws {
        guard !isSaving else { throw CategoryValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        if let id {
            try await useCases.update(id: id, name: name, nature: nature)
        } else {
            try await useCases.create(name: name, nature: nature, parentID: parentID)
        }
        await reload()
    }
}
