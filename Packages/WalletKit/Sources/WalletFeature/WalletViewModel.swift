import Combine
import Foundation
import WalletDomain

@MainActor
public final class WalletViewModel: ObservableObject {
    @Published public private(set) var entries: [WalletEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: WalletUseCases
    private var loadVersion = 0

    public init(useCases: WalletUseCases) { self.useCases = useCases }

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
            entries = loaded
        } catch is CancellationError {
            // The view's task is cancelled when it disappears.
        } catch {
            if version == loadVersion { errorMessage = error.localizedDescription }
        }
    }

    public func add() async { await mutate { try await self.useCases.add() } }

    public func delete(ids: Set<UUID>) async {
        await mutate { try await self.useCases.delete(ids: ids) }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
            await reload()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
