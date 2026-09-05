import Foundation
import SwiftData
import Testing
@testable import WalletData
import WalletDomain

// Snapshot of the account model before balances, currency and settings were added.
private enum OriginalAccountsSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Item.self, AccountRecord.self] }

    @Model
    final class AccountRecord {
        var id: UUID = UUID()
        var name: String = ""
        var typeRawValue: String = "other"
        var createdAt: Date = Date()

        init(id: UUID) {
            self.id = id
            name = "Existing Cash"
            typeRawValue = "cash"
        }
    }
}

@MainActor
struct AccountMigrationTests {
    @Test func existingAccountReceivesDefaultsWithoutLosingIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wallet.store")
        let id = UUID()

        func writeOriginalAccount() throws {
            let schema = Schema(OriginalAccountsSchema.models)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(OriginalAccountsSchema.AccountRecord(id: id))
            try context.save()
        }

        try writeOriginalAccount()
        let schema = Schema([Item.self, WalletData.AccountRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let account = try #require(try context.fetch(FetchDescriptor<WalletData.AccountRecord>()).first?.account)
        #expect(account.id == id)
        #expect(account.name == "Existing Cash")
        #expect(account.type == .cash)
        #expect(account.currencyCode == "USD")
        #expect(account.settings == AccountSettings())
    }
}
