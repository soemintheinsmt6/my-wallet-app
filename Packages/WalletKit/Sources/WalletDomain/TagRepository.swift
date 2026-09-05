import Foundation

@MainActor
public protocol TagRepository: AnyObject {
    func fetchTags() async throws -> [WalletTag]
    func createTag(name: String, color: TagColor) async throws
    func updateTag(id: UUID, name: String, color: TagColor) async throws
    func deleteTag(id: UUID) async throws
    func changes() -> AsyncStream<Void>
}
