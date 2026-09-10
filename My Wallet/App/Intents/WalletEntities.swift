import AppIntents
import Foundation
import WalletDomain

/// An account as Shortcuts sees it, so intent parameters get a real picker instead of free text.
struct AccountEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String
    let currencyCode: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Account" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(currencyCode)")
    }

    static var defaultQuery: AccountEntityQuery { AccountEntityQuery() }

    init(account: Account) {
        id = account.id
        name = account.name
        currencyCode = account.currencyCode
    }
}

struct AccountEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        let wanted = Set(identifiers)
        return try await IntentWallet.accounts().filter { wanted.contains($0.id) }.map(AccountEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        try await IntentWallet.accounts().map(AccountEntity.init)
    }
}

/// A category or subcategory, shown by its full path so "Groceries" is unambiguous.
struct CategoryEntity: AppEntity, Identifiable {
    let id: UUID
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    static var defaultQuery: CategoryEntityQuery { CategoryEntityQuery() }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        let all = try await IntentWallet.categories()
        let wanted = Set(identifiers)
        return all.filter { wanted.contains($0.id) }
            .map { CategoryEntity(id: $0.id, title: IntentWallet.title(for: $0, in: all)) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        let all = try await IntentWallet.categories()
        return all.map { CategoryEntity(id: $0.id, title: IntentWallet.title(for: $0, in: all)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
