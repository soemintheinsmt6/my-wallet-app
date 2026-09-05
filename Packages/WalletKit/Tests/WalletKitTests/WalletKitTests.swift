import Combine
import Foundation
import Testing
import WalletData
import WalletDomain
import WalletFeature

@MainActor
struct WalletKitTests {
    @Test func persistenceRoundTripAndSelectiveDelete() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let older = WalletEntry(timestamp: Date(timeIntervalSince1970: 100))
        let newer = WalletEntry(timestamp: Date(timeIntervalSince1970: 200))
        try await repository.add(older)
        try await repository.add(newer)
        #expect(try await repository.fetchEntries() == [newer, older])
        try await repository.delete(ids: [older.id])
        #expect(try await repository.fetchEntries() == [newer])
    }

    @Test func successfulWriteInvalidatesSubscribers() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let stream = repository.changes()
        try await repository.add(WalletEntry())
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test func viewModelPublishesSavedEntries() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let viewModel = WalletViewModel(useCases: WalletUseCases(repository: repository))
        var publishedCounts: [Int] = []
        let subscription = viewModel.$entries.sink { publishedCounts.append($0.count) }
        await viewModel.add()
        #expect(viewModel.entries.count == 1)
        #expect(publishedCounts.contains(1))
        await viewModel.delete(ids: Set(viewModel.entries.map(\.id)))
        #expect(viewModel.entries.isEmpty)
        #expect(!viewModel.isSaving)
        #expect(viewModel.errorMessage == nil)
        withExtendedLifetime(subscription) {}
    }

    @Test func failedWritePreservesDisplayedEntriesAndReportsError() async {
        let repository = FailingRepository()
        let viewModel = WalletViewModel(useCases: WalletUseCases(repository: repository))
        await viewModel.reload()
        await viewModel.add()
        #expect(viewModel.entries == repository.entries)
        #expect(viewModel.errorMessage != nil)
        #expect(!viewModel.isSaving)
    }

    @Test func emptyDeleteDoesNotCallRepository() async throws {
        let repository = FailingRepository()
        try await WalletUseCases(repository: repository).delete(ids: [])
    }
}

@MainActor
private final class FailingRepository: WalletRepository {
    let entries = [WalletEntry()]
    struct Failure: Error {}
    func fetchEntries() async throws -> [WalletEntry] { entries }
    func add(_ entry: WalletEntry) async throws { throw Failure() }
    func delete(ids: Set<UUID>) async throws { throw Failure() }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
