import Combine
import Foundation
import WalletDomain

@MainActor
public final class RecordsViewModel: ObservableObject {
    @Published public private(set) var records: [WalletRecord] = []
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var categories: [WalletCategory] = []
    @Published public private(set) var tags: [WalletTag] = []
    /// True until the wallet has been read once, and false from then on.
    ///
    /// Screens use it to choose between a spinner and their content, so it deliberately does not
    /// rise again for later loads: a launch runs several of them — the dashboard appearing, the
    /// recurring generator writing, the scene becoming active — and raising it each time flashed
    /// the spinner over content that was already on screen. A background load now leaves the
    /// screen as it is and swaps the data in when it lands.
    @Published public private(set) var isLoading = true
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: RecordUseCases
    private let accountUseCases: AccountUseCases
    private let categoryUseCases: CategoryUseCases
    private let tagUseCases: TagUseCases
    private var generation = 0
    private var observation: Task<Void, Never>?
    private var isReloading = false
    private var needsReload = false

    public init(useCases: RecordUseCases, accounts: AccountUseCases, categories: CategoryUseCases, tags: TagUseCases) {
        self.useCases = useCases
        accountUseCases = accounts
        categoryUseCases = categories
        tagUseCases = tags
    }

    /// Watches for changes, once, however many screens ask.
    ///
    /// The dashboard, the record list and the statistics screen all share this view model. A loop
    /// per screen meant one save fanned out into three concurrent loads, each raising `isLoading` —
    /// which the dashboard showed as its spinner flashing several times over. The loop also outlives
    /// the screen that started it, so leaving a tab no longer stops the others being kept current.
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
        generation += 1
        let version = generation
        // Assigning `false` over `false` would still publish, and redraw every screen with it.
        defer { if generation == version, isLoading { isLoading = false } }
        do {
            let accounts = try await accountUseCases.load()
            let categories = try await categoryUseCases.load()
            let tags = try await tagUseCases.load()
            let records = try await useCases.load()
            try Task.checkCancellation()
            guard version == generation else { return }
            // Only what actually changed is published: the repeated loads a launch makes read the
            // same rows back, and republishing them redrew every dashboard card — charts and
            // progress bars animating from nothing — for no change at all.
            if self.accounts != accounts { self.accounts = accounts }
            if self.categories != categories { self.categories = categories }
            if self.tags != tags { self.tags = tags }
            if self.records != records { self.records = records }
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
    /// The category or subcategory by its own name, without its parent.
    func categoryName(_ id: UUID?) -> String { category(id)?.name ?? "Uncategorized" }

    public func mostUsedCategories(for kind: RecordKind, limit: Int = 6) -> [WalletCategory] {
        let matching = records.filter { $0.draft.kind == kind }
        let counts = Dictionary(grouping: matching.compactMap { $0.draft.categoryID }, by: { $0 }).mapValues(\.count)
        let recent = Dictionary(grouping: matching.filter { $0.draft.categoryID != nil }, by: { $0.draft.categoryID! })
            .mapValues { $0.map(\.draft.date).max() ?? .distantPast }
        return Array(categories.filter { counts[$0.id] != nil }.sorted {
            if counts[$0.id] != counts[$1.id] { return counts[$0.id, default: 0] > counts[$1.id, default: 0] }
            if recent[$0.id] != recent[$1.id] { return recent[$0.id, default: .distantPast] > recent[$1.id, default: .distantPast] }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(limit))
    }
}
