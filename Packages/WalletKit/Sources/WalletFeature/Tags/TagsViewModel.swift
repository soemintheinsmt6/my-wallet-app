import Combine
import Foundation
import WalletDomain

@MainActor
public final class TagsViewModel: ObservableObject {
    @Published public private(set) var tags: [WalletTag] = []
    @Published public private(set) var isLoading = true
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: TagUseCases
    private var loadVersion = 0

    public init(useCases: TagUseCases) { self.useCases = useCases }

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
            tags = loaded
        } catch is CancellationError {
        } catch {
            if version == loadVersion { errorMessage = error.localizedDescription }
        }
    }

    public func save(id: UUID? = nil, name: String, color: TagColor) async throws {
        guard !isSaving else { throw TagValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        if let id {
            try await useCases.update(id: id, name: name, color: color)
        } else {
            try await useCases.create(name: name, color: color)
        }
        await reload()
    }

    public func delete(id: UUID) async throws {
        guard !isSaving else { throw TagValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.delete(id: id)
        await reload()
    }
}
