import WalletData
import WalletDomain
import WalletFeature

@MainActor
struct AppDependencies {
    let accountsViewModel: AccountsViewModel

    static func make() async throws -> AppDependencies {
        let repository = try await SwiftDataWalletRepository.make(
            configuration: .cloud(containerIdentifier: "iCloud.com.app.My-Wallet")
        )
        return AppDependencies(accountsViewModel: AccountsViewModel(useCases: AccountUseCases(repository: repository)))
    }
}
