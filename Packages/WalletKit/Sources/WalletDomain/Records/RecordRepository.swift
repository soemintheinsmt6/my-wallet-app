import Foundation

@MainActor
public protocol RecordRepository: AnyObject {
    func fetchRecords() async throws -> [WalletRecord]
    func createRecord(id: UUID, draft: RecordDraft) async throws
    func recordPhoto(id: UUID) async throws -> Data?
    func changes() -> AsyncStream<Void>
}
