import Foundation
import Testing
import WalletDomain
@testable import WalletFeature

struct ShortAmountTests {
    @Test func lakhCurrenciesReadInLakhsFromOneLakhUp() {
        #expect(Decimal(5_270_000).walletShort("MMK") == ("52.7", "lakhs · MMK"))
        #expect(Decimal(100_000).walletShort("MMK") == ("1", "lakh · MMK"))
        #expect(Decimal(85_000).walletShort("MMK").unit == "MMK")
        #expect(Decimal(5_270_000).walletShort("USD").unit == "USD")
    }

    @Test func chosenScaleAppliesToEveryCurrency() {
        #expect(Decimal(5_270_000).walletShort("USD", scale: .lakhs) == ("52.7", "lakhs · USD"))
        #expect(Decimal(5_270_000).walletShort("MMK", scale: .millions).unit == "MMK")
        #expect(Decimal(5_270_000).walletShort("MMK", scale: .millions).value != "52.7")
        // Below one lakh, the lakh scale falls back to the compact figure.
        #expect(Decimal(85_000).walletShort("USD", scale: .lakhs).unit == "USD")
    }

    @Test func chartAxisLabelsFollowTheChosenScale() {
        #expect(5_000_000.0.walletAxisLabel("MMK", scale: .automatic) == "50L")
        #expect(5_000_000.0.walletAxisLabel("USD", scale: .lakhs) == "50L")
        #expect(5_000_000.0.walletAxisLabel("MMK", scale: .millions) != "50L")
        #expect(50_000.0.walletAxisLabel("MMK", scale: .lakhs) != "0.5L")
    }
}

struct DashboardConfigurationTests {
    @Test func defaultsShowTheStarterCardsInOrder() {
        let configuration = DashboardConfiguration()
        #expect(configuration.visible == DashboardCard.defaultOrder)
        // Cards not in the starter set exist but stay hidden until chosen.
        #expect(configuration.hidden.contains(.spendingChart))
        #expect(configuration.hidden.contains(.goals))
    }

    /// A card added in a later release must append, not reset an arrangement already made.
    @Test func unknownCardsAreAppendedRatherThanLost() {
        var configuration = DashboardConfiguration(order: [.recent, .balance], hidden: [])
        let arranged = configuration.arranged

        #expect(arranged.prefix(2) == [.recent, .balance])
        #expect(Set(arranged) == Set(DashboardCard.allCases))
        // Everything visible, since nothing is hidden.
        #expect(configuration.visible.count == DashboardCard.allCases.count)

        configuration.setVisible(.goals, false)
        #expect(!configuration.visible.contains(.goals))
    }

    @Test func togglingACardKeepsItInTheOrder() {
        var configuration = DashboardConfiguration()
        configuration.setVisible(.spendingChart, true)

        #expect(configuration.visible.contains(.spendingChart))
        #expect(configuration.order.contains(.spendingChart))

        configuration.setVisible(.spendingChart, false)
        #expect(!configuration.visible.contains(.spendingChart))
        // Still remembered, so re-enabling restores its position.
        #expect(configuration.order.contains(.spendingChart))
    }

    @Test func reorderingMovesCards() {
        var configuration = DashboardConfiguration(order: [.balance, .summary, .recent], hidden: [])
        configuration.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(configuration.arranged.prefix(2) == [.summary, .recent])
    }

    @Test func periodsCoverTheExpectedWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_705_320_000) // 2024-01-15 12:00 UTC

        let today = ActivityPeriod.day.interval(containing: date, calendar: calendar)
        #expect(today.duration == 86400)

        let week = ActivityPeriod.week.interval(containing: date, calendar: calendar)
        #expect(week.duration == 7 * 86400)

        let month = ActivityPeriod.month.interval(containing: date, calendar: calendar)
        #expect(month.duration == 31 * 86400) // January
        #expect(month.contains(date))

        let year = ActivityPeriod.year.interval(containing: date, calendar: calendar)
        #expect(year.duration == 366 * 86400) // 2024 is a leap year
    }

    @MainActor
    @Test func theArrangementSurvivesARelaunch() {
        let name = "dashboard.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        let first = DashboardViewModel(defaults: defaults)
        first.configuration.setVisible(.goals, true)
        first.configuration.setVisible(.bills, false)

        let second = DashboardViewModel(defaults: defaults)
        #expect(second.configuration.visible.contains(.goals))
        #expect(!second.configuration.visible.contains(.bills))

        second.reset()
        #expect(DashboardViewModel(defaults: defaults).configuration.visible == DashboardCard.defaultOrder)
    }

    /// Arrangements saved before the account cards existed get them right after Balance, and the
    /// period and account scope they stored are ignored rather than failing to decode.
    @MainActor
    @Test func anOlderArrangementGainsTheAccountCardsAfterBalance() throws {
        let defaults = UserDefaults(suiteName: "dashboard.tests.\(UUID().uuidString)")!
        let older = #"{"order":["recent","balance","summary"],"hidden":["goals"],"period":"week","accountID":"\#(UUID().uuidString)"}"#
        defaults.set(Data(older.utf8), forKey: WalletPreferenceKeys.dashboard)

        let configuration = DashboardViewModel(defaults: defaults).configuration
        #expect(configuration.arranged.prefix(4) == [.recent, .balance, .accounts, .summary])
        #expect(configuration.visible.contains(.accounts))
        #expect(!configuration.visible.contains(.goals))
    }

    /// The chart cards join an older arrangement together, right after the month's summary.
    @MainActor
    @Test func anOlderArrangementGainsTheChartCardsAfterTheSummary() {
        let defaults = UserDefaults(suiteName: "dashboard.tests.\(UUID().uuidString)")!
        defaults.set(Data(#"{"order":["balance","summary","recent"],"hidden":[]}"#.utf8),
                     forKey: WalletPreferenceKeys.dashboard)

        let arranged = DashboardViewModel(defaults: defaults).configuration.arranged
        #expect(arranged.prefix(7) == [.balance, .accounts, .summary, .balanceTrend, .expenseBreakdown,
                                       .topExpenses, .recent])
    }

    /// Once the user has the card, hiding or moving it sticks across launches.
    @MainActor
    @Test func aHiddenAccountsCardStaysHidden() {
        let defaults = UserDefaults(suiteName: "dashboard.tests.\(UUID().uuidString)")!
        let first = DashboardViewModel(defaults: defaults)
        first.configuration.setVisible(.accounts, false)
        #expect(!DashboardViewModel(defaults: defaults).configuration.visible.contains(.accounts))
    }
}

struct ExpenseBreakdownTests {
    private let interval = DateInterval(start: Date(timeIntervalSince1970: 1_704_067_200), duration: 31 * 86400)
    private let cash = Account(name: "Cash", type: .cash, currencyCode: "MMK")
    private let hidden = Account(name: "Hidden", type: .cash, currencyCode: "MMK",
                                 settings: AccountSettings(excludeFromStats: true))
    private let dollars = Account(name: "Dollars", type: .cash, currencyCode: "USD")
    private let work = WalletTag(name: "Work")
    private let trip = WalletTag(name: "Trip")

    private func expense(_ amount: Decimal, on account: Account, tags: Set<UUID> = []) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = .expense
        draft.amount = amount
        draft.accountID = account.id
        draft.tagIDs = tags
        draft.date = interval.start.addingTimeInterval(86400)
        return WalletRecord(id: UUID(), draft: draft, currencyCode: account.currencyCode)
    }

    /// Unlabeled spending is its own part, a record with two labels splits between them, a label
    /// that no longer exists counts as unlabeled, and other currencies and excluded accounts stay
    /// out, so the parts add up to the month's expenses.
    @Test func labelTotalsAddUpToTheSameExpenses() {
        let records = [
            expense(100, on: cash, tags: [work.id]),
            expense(60, on: cash, tags: [work.id, trip.id]),
            expense(40, on: cash),
            expense(25, on: cash, tags: [UUID()]),
            expense(999, on: hidden, tags: [work.id]),
            expense(999, on: dollars, tags: [work.id]),
        ]
        let totals = WalletStatistics.expensesByLabel(
            records: records, accounts: [cash, hidden, dollars], tags: [work, trip],
            filter: StatisticsFilter(interval: interval, currencyCode: "MMK"))

        #expect(totals.first { $0.tagID == work.id }?.amount == 130)
        #expect(totals.first { $0.tagID == trip.id }?.amount == 30)
        #expect(totals.first { $0.tagID == nil }?.amount == 65)
        #expect(totals.reduce(Decimal.zero) { $0 + $1.amount } == 225)
        #expect(totals.first?.tagID == work.id)
    }

    /// Subcategories roll up into their top-level category, carrying its color.
    @Test func categoriesRollUpToTheirTopLevel() {
        let food = WalletCategory(name: "Food")
        let coffee = WalletCategory(parentID: food.id, name: "Coffee")
        let rent = WalletCategory(name: "Rent")
        let totals = [CategoryTotal(categoryID: coffee.id, amount: 30), CategoryTotal(categoryID: food.id, amount: 20),
                      CategoryTotal(categoryID: rent.id, amount: 40), CategoryTotal(categoryID: nil, amount: 5)]

        let entries = DashboardBreakdown.byTopLevelCategory(totals, categories: [food, coffee, rent])
        #expect(entries.map(\.name) == ["Food", "Rent", "Uncategorized"])
        #expect(entries.map(\.amount) == [50, 40, 5])
        #expect(entries.first?.color == food.colorToken.color)
    }

    /// Past the limit, the largest keep their own color and the rest become one "Other".
    @Test func aLongBreakdownFoldsTheTailIntoOther() {
        let entries = (1...8).map {
            BreakdownEntry(id: "\($0)", name: "Item \($0)", amount: Decimal(100 - $0), color: .blue)
        }
        let folded = DashboardBreakdown.folded(entries, limit: 6)

        #expect(folded.count == 6)
        #expect(folded.prefix(5).map(\.id) == ["1", "2", "3", "4", "5"])
        #expect(folded.last?.name == "Other")
        #expect(folded.last?.amount == Decimal(279)) // 94 + 93 + 92
        #expect(DashboardBreakdown.folded(Array(entries.prefix(6)), limit: 6).count == 6)
    }
}

struct AccountActivityTests {
    private let account = UUID()
    private let other = UUID()
    private let interval = DateInterval(start: Date(timeIntervalSince1970: 1_704_067_200), // 2024-01-01
                                        duration: 31 * 86400)

    private func record(_ kind: RecordKind, _ amount: Decimal, from source: UUID?, to destination: UUID? = nil,
                        day: Int) -> WalletRecord {
        var draft = RecordDraft()
        draft.kind = kind
        draft.amount = amount
        draft.accountID = source
        draft.destinationAccountID = destination
        draft.date = interval.start.addingTimeInterval(Double(day) * 86400)
        return WalletRecord(id: UUID(), draft: draft, currencyCode: "USD")
    }

    /// Income and expenses count only what was booked to this account inside the window;
    /// transfers are listed in either direction but counted in neither total.
    @Test func totalsCountOnlyThisAccountsIncomeAndExpenses() {
        let records = [
            record(.income, 500, from: account, day: 1),
            record(.expense, 120, from: account, day: 2),
            record(.expense, 999, from: other, day: 2),
            record(.transfer, 50, from: account, to: other, day: 3),
            record(.transfer, 70, from: other, to: account, day: 4),
            record(.expense, 30, from: account, day: 40),
        ]
        let activity = AccountActivity(records: records, accountID: account, interval: interval)

        #expect(activity.income == 500)
        #expect(activity.expenses == 120)
        #expect(activity.records.count == 4)
        // Newest first.
        #expect(activity.records.map(\.draft.amount) == [70, 50, 120, 500])
    }

    @Test func aWindowWithNothingInItIsEmpty() {
        let activity = AccountActivity(records: [record(.expense, 10, from: other, day: 1)],
                                       accountID: account, interval: interval)
        #expect(activity.income == 0)
        #expect(activity.expenses == 0)
        #expect(activity.records.isEmpty)
    }
}

@MainActor
struct ThemeTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "theme.tests.\(UUID().uuidString)")!
    }

    @Test func defaultsAreTheSystemLook() {
        let theme = ThemeViewModel(defaults: defaults())
        #expect(theme.accent == .system)
        #expect(theme.density == .compact)
        #expect(theme.textSize == .standard)
    }

    /// "Default" must leave the asset catalog's accent alone rather than hard-coding a blue.
    @Test func theDefaultAccentAppliesNoTint() {
        #expect(WalletAccent.system.color == nil)
        #expect(WalletAccent.green.color != nil)
        // Every accent still shows a swatch so the picker has something to render.
        for accent in WalletAccent.allCases { _ = accent.swatch }
    }

    /// Standard must not override Dynamic Type; the others only nudge it.
    @Test func textSizeOnlyNudgesTheSystemSetting() {
        #expect(WalletTextSize.standard.dynamicTypeSize == nil)
        #expect(WalletTextSize.small.dynamicTypeSize == .small)
        #expect(WalletTextSize.large.dynamicTypeSize == .large)
        #expect(WalletTextSize.larger.dynamicTypeSize == .xxLarge)
    }

    @Test func densityChangesRowPadding() {
        #expect(WalletDensity.compact.extraRowPadding == 0)
        #expect(WalletDensity.comfortable.extraRowPadding > 0)
    }

    @Test func themeChoicesSurviveARelaunch() {
        let store = defaults()
        let first = ThemeViewModel(defaults: store)
        first.accent = .teal
        first.density = .comfortable
        first.textSize = .large

        let second = ThemeViewModel(defaults: store)
        #expect(second.accent == .teal)
        #expect(second.density == .comfortable)
        #expect(second.textSize == .large)
    }

    @Test func aFailedIconChangeIsReportedAndLeavesTheIconAlone() async {
        struct Failure: Error {}
        let theme = ThemeViewModel(defaults: defaults(),
                                   iconReader: { nil },
                                   iconSetter: { _ in throw Failure() })
        await theme.setIcon("AppIcon-Forest")

        #expect(theme.iconName == nil)
        #expect(theme.errorMessage != nil)
    }
}

@MainActor
struct CategorySymbolStoreTests {
    private let category = WalletCategory(name: "Food & Drinks")

    private func store() -> CategorySymbolStore {
        CategorySymbolStore(defaults: UserDefaults(suiteName: "symbols.tests.\(UUID().uuidString)")!)
    }

    /// Without an override the seeded symbol shows, so clearing returns the shipped icon rather
    /// than a blank tile.
    @Test func theSeededSymbolIsTheFallback() {
        let symbols = store()
        #expect(symbols.symbol(for: category) == category.symbol)
        #expect(!symbols.hasOverride(category))

        symbols.set("star", for: category)
        #expect(symbols.symbol(for: category) == "star")
        #expect(symbols.hasOverride(category))

        symbols.clear(category)
        #expect(symbols.symbol(for: category) == category.symbol)
    }

    @Test func overridesSurviveARelaunchAndClearAllResetsThem() {
        let defaults = UserDefaults(suiteName: "symbols.tests.\(UUID().uuidString)")!
        let first = CategorySymbolStore(defaults: defaults)
        first.set("flame", for: category)

        let second = CategorySymbolStore(defaults: defaults)
        #expect(second.symbol(for: category) == "flame")

        second.clearAll()
        #expect(CategorySymbolStore(defaults: defaults).symbol(for: category) == category.symbol)
    }

    @Test func theOfferedSymbolsAreACuratedUniqueList() {
        let all = CategorySymbolCatalog.all
        #expect(all.count > 60)
        #expect(Set(all).count == all.count)
        #expect(all.allSatisfy { !$0.isEmpty })
    }
}

struct AccountSymbolTests {
    /// Without a choice the type decides the icon, so a type change still shows; a chosen icon
    /// wins over the type.
    @Test func theAccountTypeSymbolIsTheFallback() {
        #expect(Account(name: "Wallet", type: .cash).symbol == AccountType.cash.symbol)
        #expect(Account(name: "Wallet", type: .savings).symbol == AccountType.savings.symbol)
        #expect(Account(name: "Wallet", type: .cash, settings: AccountSettings(symbol: "star")).symbol == "star")
    }
}
