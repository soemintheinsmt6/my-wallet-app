import SwiftData

public enum WalletStorageConfiguration: Sendable {
    case cloud(containerIdentifier: String)
    case local
    case inMemory
}

public enum WalletPersistence {
    public static func makeContainer(configuration: WalletStorageConfiguration) throws -> ModelContainer {
        let schema = Schema([Item.self, AccountRecord.self, CategoryRecord.self])
        let modelConfiguration: ModelConfiguration
        switch configuration {
        case .cloud(let identifier):
            modelConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .private(identifier))
        case .local:
            modelConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        case .inMemory:
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }
}
