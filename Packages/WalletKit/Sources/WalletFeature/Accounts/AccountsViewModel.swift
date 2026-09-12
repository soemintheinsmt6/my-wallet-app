import Combine
import Foundation
import WalletDomain

@MainActor
public final class AccountsViewModel: ObservableObject {
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var isLoading = true
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: AccountUseCases
    private var loadVersion = 0
    private var observation: Task<Void, Never>?
    private var isReloading = false
    private var needsReload = false

    public init(useCases: AccountUseCases) { self.useCases = useCases }

    /// Watched once however many screens ask — the accounts list and the More screen both do — so a
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
            accounts = loaded
        } catch is CancellationError {
        } catch {
            if version == loadVersion { errorMessage = error.localizedDescription }
        }
    }

    /// A successful save dismisses the form even if a subsequent list refresh fails.
    public func create(name: String, type: AccountType, currencyCode: String = "USD", settings: AccountSettings = AccountSettings()) async throws {
        guard !isSaving else { throw AccountValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.create(name: name, type: type, currencyCode: currencyCode, settings: settings)
        await reload()
    }

    public func update(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        guard !isSaving else { throw AccountValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.update(id: id, name: name, type: type, settings: settings)
        await reload()
    }

    public func deletionImpact(id: UUID) async throws -> AccountDeletionImpact {
        try await useCases.deletionImpact(id: id)
    }

    public func delete(id: UUID, strategy: AccountDeletionStrategy) async throws {
        guard !isSaving else { throw AccountValidationError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.delete(id: id, strategy: strategy)
        await reload()
    }

    public var accountsIncludedInStats: [Account] { accounts.filter { !$0.settings.excludeFromStats } }

    public var balanceNotifications: [Account] {
        accounts.filter { $0.settings.isBelowMinimum || $0.settings.isAboveMaximum }
    }
}
