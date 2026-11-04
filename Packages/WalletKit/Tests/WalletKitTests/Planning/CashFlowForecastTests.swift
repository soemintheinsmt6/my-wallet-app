import Foundation
import Testing
@testable import WalletData
import WalletDomain
@testable import WalletFeature

struct CashFlowForecastTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-11-04 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_793_600)
    private let rent = WalletCategory(name: "Rent")

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

    private func account(_ name: String = "Checking", type: AccountType = .checking, balance: Decimal = 1000,
                         minimum: Decimal? = nil) -> Account {
        Account(name: name, type: type, currencyCode: "USD",
                settings: AccountSettings(currentBalance: balance, notifyBelowMinimum: minimum != nil,
                                          minimumBalance: minimum ?? 0))
    }

    /// A series whose first record was saved `startOffset` days from now, so `nextIndex` 1 is next.
    private func series(_ kind: RecordKind = .expense, amount: Decimal, account: Account, to destination: Account? = nil,
                        payee: String = "", startOffset: Int, frequency: RecurrenceFrequency = .weekly,
                        count: Int? = nil, state: SeriesState = .active) -> RecurringSeries {
        var draft = RecordDraft()
        draft.kind = kind
        draft.accountID = account.id
        draft.destinationAccountID = destination?.id
        draft.amount = amount
        draft.categoryID = kind == .transfer ? nil : rent.id
        draft.payee = payee
        draft.date = day(startOffset)
        return RecurringSeries(id: UUID(), template: draft,
                               rule: RecurrenceRule(frequency: frequency, count: count, timeZoneIdentifier: "UTC"),
                               state: state)
    }

    private func bill(_ name: String, amount: Decimal, account: Account, dueOffset: Int,
                      monthly: Bool = false) -> BillReminder {
        BillReminder(name: name, amount: amount, currencyCode: "USD", dueDate: day(dueOffset),
                     recurrence: monthly ? RecurrenceRule(frequency: .monthly, timeZoneIdentifier: "UTC") : nil,
                     accountID: account.id, categoryID: rent.id)
    }

    private func forecast(_ accounts: [Account], series: [RecurringSeries] = [], occurrences: [ScheduledOccurrence] = [],
                          bills: [BillReminder] = [], days: Int = 30) -> [AccountForecast] {
        CashFlowForecaster.forecast(accounts: accounts, series: series, occurrences: occurrences, bills: bills,
                                    categories: [rent], now: now, days: days, calendar: calendar)
    }

    @Test func recurringOccurrencesWithinTheHorizonMoveTheBalance() throws {
        let checking = account()
        // Saved six days ago, so next due tomorrow, then every week: days 1, 8, 15, 22 and 29.
        let groceries = series(amount: 50, account: checking, payee: "Grocer", startOffset: -6)

        let result = try #require(forecast([checking], series: [groceries]).first)
        #expect(result.events.map(\.date) == [1, 8, 15, 22, 29].map(day))
        #expect(result.events.allSatisfy { $0.amount == -50 && $0.title == "Grocer" && !$0.isOverdue })
        #expect(result.endingBalance == 750)
        #expect(result.runningBalances == [950, 900, 850, 800, 750])
        #expect(result.lowest == AccountForecast.Point(date: day(29), balance: 750))
        #expect(result.firstBelowThreshold == nil)
    }

    @Test func skippedAndModifiedOccurrencesAreHonoured() throws {
        let checking = account()
        let groceries = series(amount: 50, account: checking, startOffset: -6)
        var moved = groceries.template
        moved.amount = 80
        moved.date = day(10)
        let occurrences = [ScheduledOccurrence(seriesID: groceries.id, index: 2, skipped: true),
                           ScheduledOccurrence(seriesID: groceries.id, index: 3, overrideDraft: moved),
                           ScheduledOccurrence(seriesID: groceries.id, index: 4, completed: true)]

        let result = try #require(forecast([checking], series: [groceries], occurrences: occurrences).first)
        // Day 8 skipped, day 15 moved to day 10 at 80, day 22 already written.
        #expect(result.events.map(\.date) == [day(1), day(10), day(29)])
        #expect(result.events.map(\.amount) == [-50, -80, -50])
        // Untitled records take their category's name.
        #expect(result.events.first?.title == "Rent")
    }

    @Test func pausedCancelledAndFinishedSeriesAddNothing() {
        let checking = account()
        let paused = series(amount: 10, account: checking, startOffset: -6, state: .paused)
        let cancelled = series(amount: 10, account: checking, startOffset: -6, state: .cancelled)
        // Two records in all: the one saved and day 1.
        let short = series(amount: 10, account: checking, startOffset: -6, count: 2)

        let result = forecast([checking], series: [paused, cancelled, short])
        #expect(result.first?.events.map(\.date) == [day(1)])
    }

    @Test func anOccurrenceAlreadyDueLandsTodayAsOverdue() throws {
        let checking = account()
        // Due three days ago and not generated yet.
        let rent = series(amount: 700, account: checking, startOffset: -10, frequency: .weekly, count: 2)
        let result = try #require(forecast([checking], series: [rent]).first)
        #expect(result.events.map(\.date) == [now])
        #expect(result.events.first?.isOverdue == true)
    }

    @Test func unpaidBillsAreExpensesOnTheirAccountUntilPaid() throws {
        let checking = account()
        let phone = bill("Phone", amount: 40, account: checking, dueOffset: 5, monthly: true)
        var paid = bill("Gym", amount: 30, account: checking, dueOffset: 2)
        paid.isPaid = true
        let late = bill("Water", amount: 25, account: checking, dueOffset: -4)

        let result = try #require(forecast([checking], bills: [phone, paid, late], days: 40).first)
        #expect(result.events.map(\.title) == ["Water", "Phone", "Phone"])
        #expect(result.events.map(\.date) == [now, day(5), calendar.date(byAdding: .month, value: 1, to: day(5))!])
        #expect(result.events.first?.isOverdue == true)
        #expect(result.endingBalance == 895)
    }

    @Test func aBillARecurringExpenseAlreadyPaysIsCountedOnce() throws {
        let checking = account()
        // Rent recorded every month by a series on day 2, with a bill reminding of it on day 3.
        let rentSeries = series(amount: 700, account: checking, payee: "Landlord", startOffset: -29, frequency: .monthly)
        let reminder = bill("Rent", amount: 700, account: checking, dueOffset: 3)
        let different = bill("Insurance", amount: 120, account: checking, dueOffset: 2)

        let result = try #require(forecast([checking], series: [rentSeries], bills: [reminder, different]).first)
        #expect(result.events.map(\.title) == ["Insurance", "Landlord"])
        #expect(result.endingBalance == 180)
    }

    @Test func transfersMoveBothAccountsAndAccountsWithNothingPlannedAreLeftOut() {
        let checking = account()
        let savings = account("Savings", type: .savings, balance: 200)
        let idle = account("Idle")
        let saving = series(.transfer, amount: 100, account: checking, to: savings, startOffset: -6, count: 2)

        let result = forecast([checking, savings, idle], series: [saving])
        #expect(result.map(\.account.name) == ["Checking", "Savings"])
        #expect(result.map(\.endingBalance) == [900, 300])
        #expect(result.first?.events.first?.title == "Transfer")
    }

    @Test func theThresholdIsZeroForHeldMoneyAMinimumWhenSetAndNoneForCards() {
        #expect(CashFlowForecaster.threshold(for: account(type: .cash)) == 0)
        #expect(CashFlowForecaster.threshold(for: account(type: .savings)) == 0)
        #expect(CashFlowForecaster.threshold(for: account(type: .creditCard)) == nil)
        #expect(CashFlowForecaster.threshold(for: account(type: .loansAndMortgage)) == nil)
        #expect(CashFlowForecaster.threshold(for: account(type: .creditCard, minimum: -500)) == -500)
        #expect(CashFlowForecaster.threshold(for: account(minimum: 100)) == 100)
    }

    @Test func theFirstFallBelowTheThresholdIsReported() throws {
        let checking = account(balance: 120)
        let groceries = series(amount: 50, account: checking, startOffset: -6)
        let result = try #require(forecast([checking], series: [groceries]).first)
        // 70, 20, then -30 on day 15.
        #expect(result.firstBelowThreshold == AccountForecast.Point(date: day(15), balance: -30))

        // With a minimum of 100 set, the first purchase already takes it below.
        let guarded = account(balance: 120, minimum: 100)
        let minimum = try #require(forecast([guarded], series: [series(amount: 50, account: guarded, startOffset: -6)]).first)
        #expect(minimum.firstBelowThreshold == AccountForecast.Point(date: day(1), balance: 70))

        let overdrawn = account(balance: -5)
        let already = try #require(forecast([overdrawn], series: [series(amount: 1, account: overdrawn, startOffset: -6)]).first)
        #expect(already.firstBelowThreshold == AccountForecast.Point(date: now, balance: -5))

        let card = account("Card", type: .creditCard, balance: 0)
        let charges = try #require(forecast([card], series: [series(amount: 50, account: card, startOffset: -6)]).first)
        #expect(charges.firstBelowThreshold == nil)
        #expect(charges.lowest?.balance == -250)
    }

    @Test func dailyBalancesRunFromTodayToTheLastDay() throws {
        let checking = account()
        let groceries = series(amount: 50, account: checking, startOffset: -6)
        let result = try #require(forecast([checking], series: [groceries], days: 10).first)
        let points = result.dailyBalances(calendar: calendar)

        #expect(points.count == 11)
        #expect(points.first?.date == calendar.startOfDay(for: now))
        #expect(points.map(\.amount) == [1000, 950, 950, 950, 950, 950, 950, 950, 900, 900, 900])
        #expect(points.last?.amount == result.endingBalance)
    }
}

@MainActor
struct CashFlowForecastViewModelTests {
    @Test func accountsForecastToFallBelowComeFirstSoonestFirst() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accountUseCases = AccountUseCases(repository: repository)
        for (name, balance) in [("Calm", Decimal(5000)), ("Later", Decimal(100)), ("Soon", Decimal(20))] {
            try await accountUseCases.create(name: name, type: .checking, currencyCode: "USD",
                                             settings: AccountSettings(currentBalance: balance))
        }
        let records = RecordsViewModel(useCases: RecordUseCases(repository: repository), accounts: accountUseCases,
                                       categories: CategoryUseCases(repository: repository),
                                       tags: TagUseCases(repository: repository))
        let planning = PlanningViewModel(repository: repository, records: records)
        await planning.refresh()
        let category = try #require(records.categories.first)
        let accounts = Dictionary(uniqueKeysWithValues: records.accounts.map { ($0.name, $0.id) })
        let now = Date()
        for (name, amount, days) in [("Calm", Decimal(50), 3), ("Later", Decimal(150), 10), ("Soon", Decimal(30), 5)] {
            try await planning.save(BillReminder(name: "Bill \(name)", amount: amount, currencyCode: "USD",
                                                 dueDate: now.addingTimeInterval(Double(days) * 86400),
                                                 accountID: accounts[name], categoryID: category.id))
        }

        let forecasts = planning.forecast(now: now)
        #expect(forecasts.map(\.account.name) == ["Soon", "Later", "Calm"])
        #expect(forecasts.map { $0.firstBelowThreshold != nil } == [true, true, false])
    }

    @Test func theForecastCardIsShownAfterBillsForNewAndExistingArrangements() throws {
        #expect(DashboardConfiguration().visible.contains(.forecast))
        let order = DashboardCard.defaultOrder
        let bills = try #require(order.firstIndex(of: .bills))
        #expect(order.firstIndex(of: .forecast) == bills + 1)

        let defaults = UserDefaults(suiteName: "forecast.tests.\(UUID().uuidString)")!
        let older = #"{"order":["balance","bills","recent"],"hidden":["goals"]}"#
        defaults.set(Data(older.utf8), forKey: WalletPreferenceKeys.dashboard)
        let arranged = DashboardViewModel(defaults: defaults).configuration
        #expect(Array(arranged.visible.prefix(4)).contains(.forecast))
        let storedBills = try #require(arranged.order.firstIndex(of: .bills))
        #expect(arranged.order.firstIndex(of: .forecast) == storedBills + 1)
    }
}
