import Foundation

@MainActor
public protocol RecordRepository: AnyObject {
    func fetchRecords() async throws -> [WalletRecord]
    /// Returns the record as stored, with fields normalized and its currencies resolved.
    func createRecord(id: UUID, draft: RecordDraft) async throws -> WalletRecord
    /// Returns the record as stored, with fields normalized and its currencies resolved.
    func updateRecord(id: UUID, draft: RecordDraft) async throws -> WalletRecord
    func deleteRecord(id: UUID) async throws
    func recordPhoto(id: UUID) async throws -> Data?
    func changes() -> AsyncStream<Void>
    /// What each write did to the ledger, in order, so a screen holding every record can update
    /// just the one that changed. Every change is delivered; none is dropped or merged.
    func recordChanges() -> AsyncStream<RecordChange>
}

public extension RecordRepository {
    /// For repositories that cannot say what changed: every change asks for a full reload.
    func recordChanges() -> AsyncStream<RecordChange> { RecordChangeStreams.unknown(from: changes()) }
}

public enum RecordChangeStreams {
    /// Turns a plain change notice into "reload everything" record changes.
    public static func unknown(from changes: AsyncStream<Void>) -> AsyncStream<RecordChange> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in changes { continuation.yield(.unknown) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
