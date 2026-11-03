import Combine
import Foundation
import WalletDomain

#if canImport(WidgetKit)
    import WidgetKit
#endif

/// Keeps the widget snapshot in step with the app's data.
///
/// Subscribes to both view models and rewrites the shared snapshot after changes settle. Writes
/// are debounced because a single save publishes several times as records, accounts and budgets
/// reload in turn, and each widget timeline reload is comparatively expensive.
@MainActor
public final class WalletSnapshotCoordinator {
    private let records: RecordsViewModel
    private let planning: PlanningViewModel
    private let preferences: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var lastWritten: WalletSnapshot?
    /// Set by the app to mirror each new snapshot to a paired Apple Watch.
    public var onSnapshot: ((WalletSnapshot) -> Void)?

    public init(records: RecordsViewModel, planning: PlanningViewModel, preferences: UserDefaults = .standard) {
        self.records = records
        self.planning = planning
        self.preferences = preferences
    }

    private var numberScale: NumberScale {
        preferences.string(forKey: WalletPreferenceKeys.numberScale).flatMap(NumberScale.init(rawValue:))
            ?? .automatic
    }

    /// Starts observing. Safe to call more than once; later calls replace the subscriptions.
    public func start() {
        cancellables.removeAll()
        // Preference changes are included so a new counting choice reaches widgets and the watch;
        // unrelated preference writes are dropped by the change check in `refresh()`.
        let preferenceChanges = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: preferences)
            .map { _ in () }
        Publishers.Merge3(records.objectWillChange, planning.objectWillChange, preferenceChanges)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    /// Rebuilds and stores the snapshot, then asks WidgetKit to reload timelines.
    ///
    /// Skips the write and the reload when nothing the widgets show has changed, so background
    /// refreshes and tab switches do not churn widget updates.
    public func refresh() {
        guard !records.isLoading else { return }
        let snapshot = WalletSnapshotBuilder.make(records: records.records, accounts: records.accounts,
                                                  categories: records.categories,
                                                  budgets: planning.progress(), numberScale: numberScale)
        guard hasMeaningfulChange(from: lastWritten, to: snapshot) else { return }
        do {
            try WalletSnapshotStore.write(snapshot)
            lastWritten = snapshot
            reloadWidgets()
            onSnapshot?(snapshot)
        } catch {
            // A missing App Group container must never break the app; widgets keep their last summary.
        }
    }

    /// Clears the snapshot so widgets stop showing balances after a data reset.
    public func clear() {
        WalletSnapshotStore.clear()
        lastWritten = nil
        reloadWidgets()
    }

    /// `generatedAt` changes on every build, so compare only the content the widgets render.
    private func hasMeaningfulChange(from previous: WalletSnapshot?, to next: WalletSnapshot) -> Bool {
        guard let previous else { return true }
        return previous.balances != next.balances
            || previous.month != next.month
            || previous.recent != next.recent
            || previous.budgets != next.budgets
            || previous.numberScale != next.numberScale
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
