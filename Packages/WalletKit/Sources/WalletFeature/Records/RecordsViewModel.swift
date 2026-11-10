import Combine
import Foundation
import WalletDomain

@MainActor
public final class RecordsViewModel: ObservableObject {
    @Published public private(set) var records: [WalletRecord] = [] {
        didSet { cachedCategorizer = nil; cachedPayeeSuggestions = nil; payeeDataVersion += 1 }
    }
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var categories: [WalletCategory] = [] {
        didSet { cachedCategorizer = nil; payeeDataVersion += 1 }
    }
    /// Built by `preparePayeeData` off the main actor, or else on first use after the records or
    /// categories change; never on every keystroke of a payee.
    private var cachedCategorizer: PayeeCategorizer?
    private var cachedPayeeSuggestions: PayeeSuggestions?
    /// Bumped whenever the records or categories change, so a background build of the payee data
    /// that read an older ledger is dropped instead of cached.
    private var payeeDataVersion = 0
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
    /// Titles for the balance adjustments a lent or borrowed debt records ("Borrowed from Ana",
    /// "Repaid to Ana"), by record ID, so record rows say what they are rather than "Balance
    /// adjustment". Kept by `DebtsViewModel`, which knows which records belong to which debt.
    @Published var loanTitles: [UUID: String] = [:]
    private let useCases: RecordUseCases
    private let accountUseCases: AccountUseCases
    private let categoryUseCases: CategoryUseCases
    private let tagUseCases: TagUseCases
    private var generation = 0
    private var observation: Task<Void, Never>?
    private var isReloading = false
    private var needsReload = false
    /// Set once a full load has landed; until then a change cannot be applied in memory.
    private var hasLoaded = false

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
    ///
    /// A single saved or deleted record is applied in memory — the record spliced into the list and
    /// the balances it touches moved by its difference — so a save no longer reads every record
    /// back twice (once for the list, once to sum balances). Anything wider still reloads.
    public func observe() async {
        if observation == nil {
            // Subscribed before the first load so a change during it is not missed.
            let changes = useCases.recordChanges()
            observation = Task { [weak self] in
                for await change in changes {
                    guard let self, !Task.isCancelled else { break }
                    if !apply(change) { await reload() }
                }
            }
        }
        await reload()
    }

    /// Applies a single-record change to the records and balances in memory. Returns `false` for a
    /// change that needs a full reload. Measured against what is already held, so applying the same
    /// change twice — once by `save` and again when its notice arrives — changes nothing the second time.
    @discardableResult
    private func apply(_ change: RecordChange) -> Bool {
        // Before the first load there is nothing in memory to update, so read everything.
        guard hasLoaded,
              let updated = RecordChangeApplier.records(records, applying: change),
              let drafts = RecordChangeApplier.drafts(in: records, for: change) else { return false }
        let balances = RecordChangeApplier.accounts(accounts, movingFrom: drafts.before, to: drafts.after)
        // A load in flight read the ledger before this change; `load` sees the bump and reads again.
        generation += 1
        if accounts != balances { accounts = balances }
        if records != updated { records = updated }
        return true
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
            // A change applied meanwhile is newer than what was read, so read once more instead.
            guard version == generation else { needsReload = true; return }
            // Only what actually changed is published: the repeated loads a launch makes read the
            // same rows back, and republishing them redrew every dashboard card — charts and
            // progress bars animating from nothing — for no change at all.
            if self.accounts != accounts { self.accounts = accounts }
            if self.categories != categories { self.categories = categories }
            if self.tags != tags { self.tags = tags }
            if self.records != records { self.records = records }
            hasLoaded = true
        } catch is CancellationError {
        } catch { if version == generation { errorMessage = error.localizedDescription } }
    }

    /// Applies the saved record at once, so it is on screen when this returns; the change notice
    /// that follows finds it already there and does nothing.
    public func save(id: UUID, draft: RecordDraft, editing: Bool = false) async throws {
        guard !isSaving else { throw RecordValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        let saved = editing ? try await useCases.update(id: id, draft: draft)
                            : try await useCases.create(id: id, draft: draft)
        if !apply(.saved(saved, previous: nil, version: nil)) { await reload() }
    }

    public func delete(id: UUID) async throws {
        guard !isSaving else { throw RecordValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.delete(id: id)
        if !apply(.deleted(id, previous: nil, version: nil)) { await reload() }
    }

    public func photo(id: UUID) async throws -> Data? { try await useCases.photo(id: id) }

    /// Categories learned from the payees of the records held now.
    public var payeeCategorizer: PayeeCategorizer {
        if let cachedCategorizer { return cachedCategorizer }
        let categorizer = PayeeCategorizer(records: records, categories: categories)
        cachedCategorizer = categorizer
        return categorizer
    }

    /// The category last used for this payee, for filing a new record.
    func learnedCategory(forPayee payee: String, kind: RecordKind) -> UUID? {
        payeeCategorizer.category(forPayee: payee, kind: kind)
    }

    /// Payees already recorded that fit what has been typed, this kind of record's first.
    func payeeSuggestions(for text: String, kind: RecordKind) -> [String] {
        let suggestions = cachedPayeeSuggestions ?? PayeeSuggestions(records: records)
        cachedPayeeSuggestions = suggestions
        return suggestions.suggestions(for: text, kind: kind)
    }

    /// Builds the payee suggestions and categories off the main actor, so the record editor can
    /// start this when it opens and its Payee screen does not stall building them as it slides in.
    func preparePayeeData() async {
        guard cachedCategorizer == nil || cachedPayeeSuggestions == nil else { return }
        let version = payeeDataVersion
        let records = records
        let categories = categories
        let built = await Task.detached(priority: .userInitiated) {
            (PayeeCategorizer(records: records, categories: categories), PayeeSuggestions(records: records))
        }.value
        guard version == payeeDataVersion else { return }
        cachedCategorizer = built.0
        cachedPayeeSuggestions = built.1
    }
    func account(_ id: UUID?) -> Account? { accounts.first { $0.id == id } }
    func category(_ id: UUID?) -> WalletCategory? { categories.first { $0.id == id } }
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
