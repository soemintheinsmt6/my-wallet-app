import Combine
import Foundation
import WalletDomain

/// Shared expenses: who paid, who owes, and the fewest payments that settle up.
@MainActor
public final class SplitsViewModel: ObservableObject {
    @Published public private(set) var splits: [RecordSplit] = []
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?

    public let records: RecordsViewModel
    private let useCases: SplitUseCases
    /// Told about new owner-share figures so budgets count only the user's part.
    private let onSharesChanged: ([UUID: Decimal]) -> Void

    public init(repository: any SplitRepository, records: RecordsViewModel,
                onSharesChanged: @escaping ([UUID: Decimal]) -> Void = { _ in }) {
        useCases = SplitUseCases(repository: repository)
        self.records = records
        self.onSharesChanged = onSharesChanged
    }

    /// Net position per person across every split.
    public var balances: [String: Decimal] { SplitCalculator.balances(splits) }

    /// The currency of the splits, or the leading account currency when there are none.
    public var currencyCode: String {
        splits.first?.currencyCode ?? records.accounts.first?.currencyCode ?? "USD"
    }

    public var settlements: [SettlementSuggestion] {
        SplitCalculator.settlements(from: balances, currencyCode: currencyCode)
    }

    public func split(for recordID: UUID) -> RecordSplit? {
        splits.first { $0.recordID == recordID }
    }

    public func refresh() async {
        do {
            splits = try await useCases.load()
            onSharesChanged(SplitUseCases.ownerShares(splits))
        } catch { errorMessage = error.localizedDescription }
    }

    public func save(_ split: RecordSplit, recordAmount: Decimal) async throws {
        guard !isSaving else { throw SplitError.needsTwoParticipants }
        isSaving = true
        defer { isSaving = false }
        try await useCases.save(split, recordAmount: recordAmount)
        await refresh()
    }

    public func delete(recordID: UUID) async {
        do {
            try await useCases.delete(recordID: recordID)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}
