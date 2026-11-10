import Combine
import Foundation
import WalletDomain

/// Which proactive notices the user wants. All off by default: the app does not start notifying
/// anyone who did not ask for it.
public struct InsightPreferences: Equatable, Sendable {
    public var weeklySummary = false
    public var unusualSpending = false
    public var monthlyComparison = false
    /// Weekday for the weekly summary, 1 = Sunday to match `Calendar`.
    public var weeklyWeekday = 2
    public var hour = 9

    public var isAnyEnabled: Bool { weeklySummary || unusualSpending || monthlyComparison }

    public init() {}
}

/// Computes insights and schedules the notices the user has opted into.
@MainActor
public final class InsightsViewModel: ObservableObject {
    @Published public private(set) var insights = WalletInsights()
    @Published public var errorMessage: String?
    /// Whether system notifications are already allowed, so the request button can be hidden.
    /// Starts true so the button does not flash before the first check in the usual case.
    @Published public private(set) var notificationsAuthorized = true
    @Published public var preferences: InsightPreferences {
        didSet {
            guard preferences != oldValue else { return }
            save(preferences)
            Task { await synchronizeNotifications() }
        }
    }

    private let records: RecordsViewModel
    private let planning: PlanningViewModel?
    private let notifications: (any WalletNotificationClient)?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = []

    public init(records: RecordsViewModel, planning: PlanningViewModel? = nil,
                notifications: (any WalletNotificationClient)? = nil,
                defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.records = records
        self.planning = planning
        self.notifications = notifications
        self.defaults = defaults
        self.now = now
        preferences = Self.load(from: defaults)
    }

    /// Recomputes whenever the wallet changes, debounced like the widget snapshot.
    public func start() {
        cancellables.removeAll()
        records.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    public func refresh() {
        insights = WalletInsightsCalculator.calculate(records: records.records,
                                                      accounts: records.accounts,
                                                      budgets: planning?.progress() ?? [],
                                                      now: now())
        Task { await synchronizeNotifications() }
    }

    public func requestAuthorization() async {
        do {
            guard let notifications, try await notifications.requestAuthorization() else {
                notificationsAuthorized = false
                errorMessage = "Notifications are disabled. Enable them for My Wallet in system settings."
                return
            }
            notificationsAuthorized = true
            await synchronizeNotifications()
        } catch { errorMessage = error.localizedDescription }
    }

    public func refreshNotificationAuthorization() async {
        guard let notifications else { return }
        notificationsAuthorized = await notifications.isAuthorized()
    }

    /// Builds the notices for whatever is switched on and hands them to the client.
    ///
    /// Always synchronizes, even with nothing enabled, so turning a preference off cancels the
    /// notice it had scheduled.
    private func synchronizeNotifications() async {
        guard let notifications else { return }
        var notices: [WalletNotification] = []
        let calendar = Calendar.current

        if preferences.weeklySummary, let week = insights.week,
           let date = nextWeeklyDate(calendar: calendar) {
            let spent = week.current.walletFormattedForNotice(week.currencyCode)
            let trend = week.change.map { change in
                let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
                return week.isHigher ? " — \(percent) more than the week before."
                                     : " — \(percent) less than the week before."
            } ?? "."
            notices.append(WalletNotification(
                id: "wallet.insight.weekly.\(Int(date.timeIntervalSince1970))",
                title: "Your week in My Wallet",
                body: "You spent \(spent) this week\(trend)",
                date: date))
        }

        if preferences.unusualSpending, let anomaly = insights.anomalies.first {
            let spent = anomaly.current.walletFormattedForNotice(anomaly.currencyCode)
            let usual = anomaly.average.walletFormattedForNotice(anomaly.currencyCode)
            let name = records.categoryName(anomaly.categoryID)
            // Keyed by month so the same category alerts at most once per month.
            notices.append(WalletNotification(
                id: "wallet.insight.unusual.\(anomaly.categoryID).\(monthKey(calendar: calendar))",
                title: "Unusual spending: \(name)",
                body: "\(spent) so far this month, against a usual \(usual)."))
        }

        if preferences.monthlyComparison, let month = insights.month, month.previous > 0,
           let date = nextMonthStart(calendar: calendar) {
            let spent = month.current.walletFormattedForNotice(month.currencyCode)
            let previous = month.previous.walletFormattedForNotice(month.currencyCode)
            notices.append(WalletNotification(
                id: "wallet.insight.month.\(Int(date.timeIntervalSince1970))",
                title: "Last month in My Wallet",
                body: "You spent \(spent), against \(previous) the month before.",
                date: date))
        }

        do {
            try await notifications.synchronize(notices,
                                                managing: type(of: notifications).insightPrefixes)
        } catch { errorMessage = error.localizedDescription }
    }

    private func nextWeeklyDate(calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.weekday = preferences.weeklyWeekday
        components.hour = preferences.hour
        components.minute = 0
        return calendar.nextDate(after: now(), matching: components, matchingPolicy: .nextTime)
    }

    /// The first morning of next month, when a full month is available to compare.
    private func nextMonthStart(calendar: Calendar) -> Date? {
        guard let month = calendar.dateInterval(of: .month, for: now()) else { return nil }
        return calendar.date(byAdding: .hour, value: preferences.hour, to: month.end)
    }

    private func monthKey(calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    // MARK: - Preferences

    private static func load(from defaults: UserDefaults) -> InsightPreferences {
        var preferences = InsightPreferences()
        preferences.weeklySummary = defaults.bool(forKey: WalletPreferenceKeys.insightWeekly)
        preferences.unusualSpending = defaults.bool(forKey: WalletPreferenceKeys.insightUnusual)
        preferences.monthlyComparison = defaults.bool(forKey: WalletPreferenceKeys.insightMonthly)
        if let weekday = defaults.object(forKey: WalletPreferenceKeys.insightWeekday) as? Int {
            preferences.weeklyWeekday = weekday
        }
        if let hour = defaults.object(forKey: WalletPreferenceKeys.insightHour) as? Int {
            preferences.hour = hour
        }
        return preferences
    }

    private func save(_ preferences: InsightPreferences) {
        defaults.set(preferences.weeklySummary, forKey: WalletPreferenceKeys.insightWeekly)
        defaults.set(preferences.unusualSpending, forKey: WalletPreferenceKeys.insightUnusual)
        defaults.set(preferences.monthlyComparison, forKey: WalletPreferenceKeys.insightMonthly)
        defaults.set(preferences.weeklyWeekday, forKey: WalletPreferenceKeys.insightWeekday)
        defaults.set(preferences.hour, forKey: WalletPreferenceKeys.insightHour)
    }
}

extension Decimal {
    /// Notification text is read at a glance; cents rarely help there.
    func walletFormattedForNotice(_ currencyCode: String) -> String {
        formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
    }
}
