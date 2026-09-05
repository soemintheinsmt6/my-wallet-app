import Combine
import CoreData
import Foundation
import SwiftData
import WalletDomain

@MainActor
public final class SwiftDataWalletRepository: WalletRepository, AccountRepository {
    private let store: WalletStore
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    private init(store: WalletStore) {
        self.store = store
        // SwiftData's CloudKit backing store posts notifications after remote imports.
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .sink { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.notifyChanges() }
            }
            .store(in: &subscriptions)
    }

    public static func make(configuration: WalletStorageConfiguration) async throws -> SwiftDataWalletRepository {
        let store = try await Task.detached {
            let container = try WalletPersistence.makeContainer(configuration: configuration)
            return WalletStore(modelContainer: container)
        }.value
        return SwiftDataWalletRepository(store: store)
    }

    public func fetchEntries() async throws -> [WalletEntry] { try await store.fetchEntries() }

    public func fetchAccounts() async throws -> [Account] { try await store.fetchAccounts() }

    public func updateAccount(id: UUID, name: String, type: AccountType, settings: AccountSettings) async throws {
        try await store.updateAccount(id: id, name: name, type: type, settings: settings)
        notifyChanges()
    }

    public func createAccount(_ account: Account) async throws {
        try await store.createAccount(account)
        notifyChanges()
    }

    public func add(_ entry: WalletEntry) async throws {
        try await store.add(entry)
        notifyChanges()
    }

    public func delete(ids: Set<UUID>) async throws {
        try await store.delete(ids: ids)
        notifyChanges()
    }

    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.observers.removeValue(forKey: id) }
        }
        return stream
    }

    private func notifyChanges() {
        for observer in observers.values { observer.yield(()) }
    }

    deinit {
        for observer in observers.values { observer.finish() }
    }
}
