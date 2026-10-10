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

        let today = DashboardPeriod.today.interval(containing: date, calendar: calendar)
        #expect(today.duration == 86400)

        let week = DashboardPeriod.week.interval(containing: date, calendar: calendar)
        #expect(week.duration == 7 * 86400)

        let month = DashboardPeriod.month.interval(containing: date, calendar: calendar)
        #expect(month.duration == 31 * 86400) // January
        #expect(month.contains(date))
    }

    @MainActor
    @Test func theArrangementSurvivesARelaunch() {
        let name = "dashboard.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        let first = DashboardViewModel(defaults: defaults)
        first.configuration.setVisible(.goals, true)
        first.configuration.period = .week

        let second = DashboardViewModel(defaults: defaults)
        #expect(second.configuration.visible.contains(.goals))
        #expect(second.configuration.period == .week)

        second.reset()
        #expect(second.configuration.period == .month)
        #expect(DashboardViewModel(defaults: defaults).configuration.visible == DashboardCard.defaultOrder)
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
