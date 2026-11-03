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
    private var observation: Task<Void, Never>?
    private var isReloading = false
    private var needsReload = false
    private let preferences: UserDefaults
    private var isMigratingLocalSymbols = false

    public init(useCases: CategoryUseCases, preferences: UserDefaults = .standard) {
        self.useCases = useCases
        self.preferences = preferences
    }

    public var rootCategories: [WalletCategory] { categories.filter { $0.parentID == nil } }
    public func subcategories(of id: UUID) -> [WalletCategory] { categories.filter { $0.parentID == id } }
    public func category(id: UUID) -> WalletCategory? { categories.first { $0.id == id } }

    /// Watched once however many screens ask — the categories list and the More screen both do — so
    /// a change costs one load rather than one per screen.
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
            categories = loaded
            await migrateLocalSymbols(into: loaded)
        } catch is CancellationError {
        } catch {
            if version == loadVersion { errorMessage = error.localizedDescription }
        }
    }

    /// Sets a category's icon, or resets it to the starter icon with `nil`. The list shows the new
    /// icon at once; the save then syncs it, and a failure puts the stored icon back.
    public func setSymbol(_ symbolName: String?, for id: UUID) async {
        if let index = categories.firstIndex(where: { $0.id == id }) {
            let current = categories[index]
            categories[index] = WalletCategory(id: current.id, parentID: current.parentID, name: current.name,
                                               nature: current.nature, sortOrder: current.sortOrder,
                                               symbolName: symbolName)
        }
        do {
            try await useCases.setSymbol(id: id, symbolName: symbolName)
        } catch is CancellationError {
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    /// Builds before 2026-11 kept icon choices in this device's preferences, keyed by category ID.
    /// Each is copied onto its category once, unless the category already carries an icon (one
    /// synced from another device wins), and the local copy is removed when every write succeeded.
    private func migrateLocalSymbols(into loaded: [WalletCategory]) async {
        let key = WalletPreferenceKeys.legacyCategorySymbols
        guard !isMigratingLocalSymbols,
              let local = preferences.dictionary(forKey: key) as? [String: String], !local.isEmpty else { return }
        isMigratingLocalSymbols = true
        defer { isMigratingLocalSymbols = false }
        let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var allSaved = true
        for (idString, symbol) in local {
            // A deleted category, or one that already has an icon, has nothing to take over.
            guard let id = UUID(uuidString: idString), let category = byID[id], category.symbolName == nil else { continue }
            do { try await useCases.setSymbol(id: id, symbolName: symbol) } catch { allSaved = false }
        }
        if allSaved { preferences.removeObject(forKey: key) }
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
