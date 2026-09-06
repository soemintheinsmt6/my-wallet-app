import Foundation

@MainActor
public protocol RecordRepository: AnyObject {
    func fetchRecords() async throws -> [WalletRecord]
    func createRecord(id: UUID, draft: RecordDraft) async throws
    func updateRecord(id: UUID, draft: RecordDraft) async throws
    func deleteRecord(id: UUID) async throws
    func recordPhoto(id: UUID) async throws -> Data?
    func changes() -> AsyncStream<Void>
}
