import Foundation
import Testing
import WalletDomain
@testable import WalletFeature

struct InsightsTests {
    /// Mid-month, mid-week, midday so no assertion sits on a boundary by accident.
    private let now = Date(timeIntervalSince1970: 1_705_320_000) // 2024-01-15 12:00 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func account(_ name: String = "Cash", currency: String = "USD",
                         excluded: Bool = false) -> Account {
        Account(name: name, type: .cash, currencyCode: currency,
                settings: AccountSettings(excludeFromStats: excluded))
    }

    private func record(_ amount: Decimal, account: Account, category: UUID? = nil,
                        daysAgo: Double = 0, kind: RecordKind = .expense) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = account.id
        draft.amount = amount
        draft.categoryID = category
        draft.date = now.addingTimeInterval(-daysAgo * 86400)
        return WalletRecord(id: UUID(), draft: draft, currencyCode: account.currencyCode)
    }

    // MARK: - Comparisons

    @Test func weekAndMonthCompareAgainstThePrecedingPeriod() {
        let cash = account()
        let records = [
            record(30, account: cash),                 // this week, this month
            record(20, account: cash, daysAgo: 8),     // last week, this month
            record(50, account: cash, daysAgo: 20),    // last month
        ]
        let insights = WalletInsightsCalculator.calculate(records: records, accounts: [cash],
                                                          now: now, calendar: calendar)

        #expect(insights.week?.current == 30)
        #expect(insights.week?.previous == 20)
        #expect(insights.week?.isHigher == true)
        #expect(insights.month?.current == 50)
        #expect(insights.month?.previous == 50)
        #expect(insights.month?.isHigher == false)
    }

    /// "Up 100% from nothing" is misleading, so a percentage is withheld instead.
    @Test func percentageChangeIsWithheldWithoutAPriorPeriod() {
        let none = WalletInsights.Comparison(currencyCode: "USD", current: 40, previous: 0)
        #expect(none.change == nil)
        #expect(none.difference == 40)

        let both = WalletInsights.Comparison(currencyCode: "USD", current: 150, previous: 100)
        #expect(both.change == 0.5)
    }

    @Test func transfersIncomeAndExcludedAccountsDoNotCountAsSpending() {
        let cash = account()
        let hidden = account("Hidden", excluded: true)
        let records = [
            record(30, account: cash),
            record(500, account: cash, kind: .income),
            record(400, account: cash, kind: .transfer),
            record(90, account: hidden),
        ]
        let insights = WalletInsightsCalculator.calculate(records: records, accounts: [cash, hidden],
                                                          now: now, calendar: calendar)
        #expect(insights.week?.current == 30)
    }

    // MARK: - Anomalies

    @Test func aCategorySpendingWellAboveItsOwnAverageIsFlagged() {
        let cash = account()
        let coffee = UUID()
        // 100 this month against 20 a month for the previous three.
        var records = [record(100, account: cash, category: coffee)]
        for month in 1...3 {
            records.append(record(20, account: cash, category: coffee, daysAgo: Double(month) * 31))
        }
        let insights = WalletInsightsCalculator.calculate(records: records, accounts: [cash],
                                                          now: now, calendar: calendar)

        let anomaly = try? #require(insights.anomalies.first)
        #expect(anomaly?.categoryID == coffee)
        #expect(anomaly?.current == 100)
        #expect(anomaly?.average == 20)
        #expect((anomaly?.multiple ?? 0) == 5)
    }

    @Test func steadySpendingAndSmallAmountsAreNotFlagged() {
        let cash = account()
        let steady = UUID()
        let tiny = UUID()
        var records = [record(20, account: cash, category: steady),
                       record(12, account: cash, category: tiny)]
        for month in 1...3 {
            records.append(record(20, account: cash, category: steady, daysAgo: Double(month) * 31))
            // A trivial history, so `tiny` is 12 against ~1 — a big multiple on a small amount.
            records.append(record(1, account: cash, category: tiny, daysAgo: Double(month) * 31))
        }
        let insights = WalletInsightsCalculator.calculate(records: records, accounts: [cash],
                                                          now: now, calendar: calendar)

        #expect(!insights.anomalies.contains { $0.categoryID == steady })
        // 12 clears the minimum, so this one is reported; below the minimum it would not be.
        #expect(insights.anomalies.contains { $0.categoryID == tiny })
    }

    @Test func spendingBelowTheMinimumIsNeverFlagged() {
        let cash = account()
        let sweets = UUID()
        var records = [record(9, account: cash, category: sweets)]
        for month in 1...3 {
            records.append(record(1, account: cash, category: sweets, daysAgo: Double(month) * 31))
        }
        let insights = WalletInsightsCalculator.calculate(records: records, accounts: [cash],
                                                          now: now, calendar: calendar)
        #expect(insights.anomalies.isEmpty)
    }

    // MARK: - Streaks

    @Test func loggingStreakCountsConsecutiveDaysBackFromToday() {
        let cash = account()
        let records = (0..<4).map { record(5, account: cash, daysAgo: Double($0)) }
        #expect(WalletInsightsCalculator.loggingStreak(records, now: now, calendar: calendar) == 4)
    }

    /// The day is not over, so a streak that reaches yesterday is still alive.
    @Test func aStreakEndingYesterdayStillCounts() {
        let cash = account()
        let records = (1...3).map { record(5, account: cash, daysAgo: Double($0)) }
        #expect(WalletInsightsCalculator.loggingStreak(records, now: now, calendar: calendar) == 3)
    }

    @Test func aGapBreaksTheStreakAndNoRecordsMeansNoStreak() {
        let cash = account()
        let broken = [record(5, account: cash), record(5, account: cash, daysAgo: 3)]
        #expect(WalletInsightsCalculator.loggingStreak(broken, now: now, calendar: calendar) == 1)

        let stale = [record(5, account: cash, daysAgo: 5)]
        #expect(WalletInsightsCalculator.loggingStreak(stale, now: now, calendar: calendar) == 0)
        #expect(WalletInsightsCalculator.loggingStreak([], now: now, calendar: calendar) == 0)
    }

    @Test func severalRecordsInOneDayCountOnce() {
        let cash = account()
        let records = [record(5, account: cash), record(6, account: cash), record(7, account: cash)]
        #expect(WalletInsightsCalculator.loggingStreak(records, now: now, calendar: calendar) == 1)
    }

    @Test func anEmptyWalletProducesNoInsights() {
        let insights = WalletInsightsCalculator.calculate(records: [], accounts: [], now: now,
                                                          calendar: calendar)
        #expect(insights.isEmpty)
    }
}

@MainActor
struct InsightPreferencesTests {
    @Test func everyNoticeIsOffUntilTurnedOn() {
        let preferences = InsightPreferences()
        #expect(!preferences.weeklySummary)
        #expect(!preferences.unusualSpending)
        #expect(!preferences.monthlyComparison)
        #expect(!preferences.isAnyEnabled)
    }

    /// Planning and insight notices must not cancel each other.
    @Test func planningAndInsightNoticesOwnDistinctPrefixes() {
        let planning = LocalNotificationDouble.planningPrefixes
        let insight = LocalNotificationDouble.insightPrefixes
        #expect(!planning.isEmpty)
        #expect(!insight.isEmpty)
        for prefix in insight {
            #expect(!planning.contains { $0.hasPrefix(prefix) || prefix.hasPrefix($0) })
        }
    }
}

/// Only used to reach the protocol's default prefixes from a test.
private final class LocalNotificationDouble: WalletNotificationClient {
    func requestAuthorization() async throws -> Bool { true }
    func synchronize(_ notifications: [WalletNotification], managing prefixes: [String]) async throws {}
}
