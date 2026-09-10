import WalletData
import WalletDomain
import WalletFeature

@MainActor
struct AppDependencies {
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    let tagsViewModel: TagsViewModel
    let recordsViewModel: RecordsViewModel
    let planningViewModel: PlanningViewModel
    let settingsViewModel: SettingsViewModel
    /// Keeps the shared widget snapshot in step with the wallet's data.
    let snapshotCoordinator: WalletSnapshotCoordinator
    let appLockViewModel: AppLockViewModel

    static func make() async throws -> AppDependencies {
        let repository = try await SwiftDataWalletRepository.make(
            configuration: .cloud(containerIdentifier: "iCloud.com.app.My-Wallet")
        )
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: AccountUseCases(repository: repository), categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let planning = PlanningViewModel(repository: repository, records: records, notifications: LocalWalletNotifications())
        let snapshots = WalletSnapshotCoordinator(records: records, planning: planning)
        let settings = SettingsViewModel(resetUseCase: ResetWalletUseCase(repository: repository))
        // Widgets must stop showing balances as soon as the wallet is cleared.
        settings.onReset = { [weak snapshots] in snapshots?.clear() }
        return AppDependencies(
            accountsViewModel: AccountsViewModel(useCases: AccountUseCases(repository: repository)),
            categoriesViewModel: CategoriesViewModel(useCases: CategoryUseCases(repository: repository)),
            tagsViewModel: TagsViewModel(useCases: TagUseCases(repository: repository)),
            recordsViewModel: records,
            planningViewModel: planning,
            settingsViewModel: settings,
            snapshotCoordinator: snapshots,
            appLockViewModel: AppLockViewModel()
        )
    }
}
