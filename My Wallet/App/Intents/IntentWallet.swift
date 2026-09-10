import Foundation
import WalletData
import WalletDomain

/// Opens the wallet for App Intents.
///
/// Intents can run without the UI having launched, so they cannot reuse `AppBootstrap`. The
/// container is built once per process and shared, because opening a CloudKit-backed SwiftData
/// container is expensive and Shortcuts may run several intents in a row.
@MainActor
enum IntentWallet {
    private static var repository: SwiftDataWalletRepository?

    static func open() async throws -> SwiftDataWalletRepository {
        if let repository { return repository }
        let opened = try await SwiftDataWalletRepository.make(
            configuration: .cloud(containerIdentifier: "iCloud.com.app.My-Wallet")
        )
        repository = opened
        return opened
    }

    static func accounts() async throws -> [Account] {
        try await AccountUseCases(repository: try await open()).load()
    }

    static func categories() async throws -> [WalletCategory] {
        try await CategoryUseCases(repository: try await open()).load()
    }

    /// Full "Parent / Child" name, matching how categories read everywhere else.
    static func title(for category: WalletCategory, in all: [WalletCategory]) -> String {
        guard let parent = category.parentID.flatMap({ id in all.first { $0.id == id } }) else {
            return category.name
        }
        return "\(parent.name) / \(category.name)"
    }

    /// The widget snapshot, used by the read-only intents so they answer instantly without
    /// opening the store at all.
    static func snapshot() -> WalletSnapshot? { WalletSnapshotStore.read() }
}

enum IntentError: LocalizedError {
    case noAccounts
    case unknownAccount(String)
    case invalidAmount
    case noData

    var errorDescription: String? {
        switch self {
        case .noAccounts: "Create an account in My Wallet first."
        case .unknownAccount(let name): "There is no account named “\(name)” in My Wallet."
        case .invalidAmount: "Enter an amount greater than zero."
        case .noData: "Open My Wallet once so it can prepare your summary."
        }
    }
}
