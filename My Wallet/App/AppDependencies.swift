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
    let dataExchangeViewModel: DataExchangeViewModel
    let onboardingViewModel: OnboardingViewModel
    let currencyViewModel: CurrencyViewModel
    let spotlightIndexer: WalletSpotlightIndexer
    let watchConnector: PhoneWatchConnector

    static func make() async throws -> AppDependencies {
        let repository = try await SwiftDataWalletRepository.make(
            configuration: .cloud(containerIdentifier: "iCloud.com.app.My-Wallet")
        )
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: AccountUseCases(repository: repository), categories: CategoryUseCases(repository: repository), tags: TagUseCases(repository: repository))
        let planning = PlanningViewModel(repository: repository, records: records, notifications: LocalWalletNotifications())
        let snapshots = WalletSnapshotCoordinator(records: records, planning: planning)
        let rateCache = ExchangeRateCache()
        let currency = CurrencyViewModel(provider: FrankfurterExchangeRateProvider(),
                                         load: { rateCache.load() },
                                         store: { rateCache.save($0) })
        let accounts = AccountsViewModel(useCases: AccountUseCases(repository: repository))
        let settings = SettingsViewModel(resetUseCase: ResetWalletUseCase(repository: repository))
        let spotlight = WalletSpotlightIndexer()
        let watch = PhoneWatchConnector()
        // Mirror every new snapshot to the watch, and write back whatever the watch captured.
        snapshots.onSnapshot = { [weak watch] in watch?.send($0) }
        watch.saveExpense = { [weak records] expense in
            var draft = RecordDraft()
            draft.kind = .expense
            draft.accountID = expense.accountID
            draft.categoryID = expense.categoryID
            draft.amount = expense.amount
            draft.date = expense.date
            // Goes through the normal use case, so a watch capture is validated like any record.
            try? await RecordUseCases(repository: repository).create(id: expense.id, draft: draft)
            await records?.reload()
        }
        // Widgets and Spotlight must stop showing wallet data as soon as it is cleared.
        settings.onReset = { [weak snapshots] in
            snapshots?.clear()
            spotlight.clear()
        }
        return AppDependencies(
            accountsViewModel: accounts,
            categoriesViewModel: CategoriesViewModel(useCases: CategoryUseCases(repository: repository)),
            tagsViewModel: TagsViewModel(useCases: TagUseCases(repository: repository)),
            recordsViewModel: records,
            planningViewModel: planning,
            settingsViewModel: settings,
            snapshotCoordinator: snapshots,
            appLockViewModel: AppLockViewModel(),
            dataExchangeViewModel: DataExchangeViewModel(
                records: records,
                recordUseCases: RecordUseCases(repository: repository),
                tagUseCases: TagUseCases(repository: repository)
            ),
            onboardingViewModel: OnboardingViewModel(accounts: accounts, planning: planning),
            currencyViewModel: currency,
            spotlightIndexer: spotlight,
            watchConnector: watch
        )
    }
}
