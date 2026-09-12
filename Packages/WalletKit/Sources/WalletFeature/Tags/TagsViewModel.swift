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
    private var observation: Task<Void, Never>?
    private var isReloading = false
    private var needsReload = false

    public init(useCases: TagUseCases) { self.useCases = useCases }

    /// Watched once however many screens ask — the labels list and the More screen both do — so a
    /// change costs one load rather than one per screen.
    public func observe() async {
        if observation == nil {
            // Subscribed before the first load so a change during it is not missed.
            let changes = useCases.changes()
            observation = Task { [weak self] in
                for await _ in changes {
                    guard let self, !Task.isCancelled else { break }
                    await reload()
                }
            }
        }
        await reload()
    }

    /// Folds into the load already running rather than racing it, and runs once more afterwards if
    /// something changed while it was in flight.
    public func reload() async {
        guard !isReloading else { needsReload = true; return }
        isReloading = true
        defer { isReloading = false }
        repeat {
            needsReload = false
            await load()
        } while needsReload
    }

    private func load() async {
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
