import Foundation
import Testing
import WalletData
import WalletDomain
@testable import WalletFeature

private struct StubRateProvider: ExchangeRateProviding {
    var set: ExchangeRateSet?
    var error: (any Error)?
    var supported: Set<String>?

    var supportedCurrencies: Set<String>? { supported }

    func rates(base: String, on date: Date?) async throws -> ExchangeRateSet {
        if let error { throw error }
        guard let set else { throw ExchangeRateError.unavailable }
        return set
    }
}

struct CurrencyConverterTests {
    /// EUR-based, like the public feed this app reads.
    private let rates = ExchangeRateSet(
        base: "EUR", date: Date(),
        rates: ["USD": Decimal(string: "1.10")!, "GBP": Decimal(string: "0.85")!, "JPY": 160])

    @Test func convertingToTheSameCurrencyIsExact() throws {
        #expect(try CurrencyConverter.rate(from: "USD", to: "USD", using: rates) == 1)
        #expect(try CurrencyConverter.convert(42, from: "USD", to: "USD", using: rates) == 42)
    }

    @Test func ratesAgainstTheBaseAreUsedDirectly() throws {
        #expect(try CurrencyConverter.rate(from: "EUR", to: "USD", using: rates) == Decimal(string: "1.10"))
        #expect(try CurrencyConverter.convert(100, from: "EUR", to: "USD", using: rates) == 110)
    }

    /// A EUR-quoted table must still convert USD to GBP by crossing through the base.
    @Test func crossRatesGoThroughTheBase() throws {
        let rate = try CurrencyConverter.rate(from: "USD", to: "GBP", using: rates)
        #expect(rate == Decimal(string: "0.85")! / Decimal(string: "1.10")!)
        #expect(try CurrencyConverter.convert(110, from: "USD", to: "GBP", using: rates) == 85)
    }

    @Test func aMissingCurrencyIsReportedRatherThanGuessed() {
        #expect(throws: ExchangeRateError.missingRate(from: "EUR", to: "CHF")) {
            try CurrencyConverter.rate(from: "EUR", to: "CHF", using: rates)
        }
    }

    /// Zero-decimal currencies must not gain cents.
    @Test func resultsRoundToTheTargetCurrencysPrecision() throws {
        #expect(CurrencyConverter.fractionDigits(for: "JPY") == 0)
        #expect(CurrencyConverter.fractionDigits(for: "USD") == 2)
        #expect(try CurrencyConverter.convert(1, from: "EUR", to: "JPY", using: rates) == 160)
        // 10 EUR at 0.85 is 8.50 GBP exactly; 10.004 rounds to two places.
        #expect(try CurrencyConverter.convert(Decimal(string: "10.004")!, from: "EUR", to: "GBP", using: rates)
                == Decimal(string: "8.50")!)
    }

    @Test func anExplicitRateIsUsedWhenGiven() throws {
        #expect(try CurrencyConverter.convert(100, to: "USD", rate: Decimal(string: "1.25")!) == 125)
        #expect(throws: ExchangeRateError.invalidRate) {
            try CurrencyConverter.convert(100, to: "USD", rate: 0)
        }
    }

    @Test func staleRatesAreRefreshedAndFreshOnesAreNot() {
        let now = Date()
        #expect(ExchangeRatePolicy.needsRefresh(nil, now: now))

        let fresh = ExchangeRateSet(base: "EUR", date: now, rates: [:], fetchedAt: now)
        #expect(!ExchangeRatePolicy.needsRefresh(fresh, now: now.addingTimeInterval(3600)))
        #expect(ExchangeRatePolicy.needsRefresh(fresh, now: now.addingTimeInterval(ExchangeRatePolicy.refreshInterval)))
        // A backwards clock refreshes rather than trusting the cache forever.
        #expect(ExchangeRatePolicy.needsRefresh(fresh, now: now.addingTimeInterval(-60)))
    }
}

@MainActor
struct CurrencyViewModelTests {
    private let rates = ExchangeRateSet(
        base: "USD", date: Date(),
        rates: ["EUR": Decimal(string: "0.90")!, "GBP": Decimal(string: "0.80")!])

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "currency.tests.\(UUID().uuidString)")!
    }

    private func model(provider: StubRateProvider, main: String = "USD",
                       converts: Bool = true, cached: ExchangeRateSet? = nil) -> CurrencyViewModel {
        let defaults = freshDefaults()
        defaults.set(main, forKey: WalletPreferenceKeys.mainCurrency)
        defaults.set(converts, forKey: WalletPreferenceKeys.convertTotals)
        return CurrencyViewModel(provider: provider, preferences: defaults, load: { cached })
    }

    @Test func conversionIsUnavailableUntilRatesArriveAndTheUserOptsIn() async {
        let off = model(provider: StubRateProvider(set: rates), converts: false, cached: rates)
        #expect(!off.isConversionAvailable)

        let noRates = model(provider: StubRateProvider(error: ExchangeRateError.unavailable))
        #expect(!noRates.isConversionAvailable)

        let ready = model(provider: StubRateProvider(set: rates), cached: rates)
        #expect(ready.isConversionAvailable)
    }

    @Test func mainCurrencyStartsAsKyatAndPersistsAChange() {
        let defaults = freshDefaults()
        let first = CurrencyViewModel(provider: StubRateProvider(set: rates), preferences: defaults)
        #expect(first.mainCurrency == "MMK")
        first.mainCurrency = "THB"
        let reopened = CurrencyViewModel(provider: StubRateProvider(set: rates), preferences: defaults)
        #expect(reopened.mainCurrency == "THB")
    }

    /// Someone converting totals keeps the currency those totals were shown in; anyone else keeps
    /// the one new items started in. The replaced keys are removed after carrying over.
    @Test func separateHomeAndDefaultCurrenciesMergeIntoTheMainCurrency() {
        let converting = freshDefaults()
        converting.set("USD", forKey: WalletPreferenceKeys.legacyHomeCurrency)
        converting.set("MMK", forKey: WalletPreferenceKeys.legacyDefaultCurrency)
        converting.set(true, forKey: WalletPreferenceKeys.convertTotals)
        let first = CurrencyViewModel(provider: StubRateProvider(set: rates), preferences: converting)
        #expect(first.mainCurrency == "USD")
        #expect(converting.string(forKey: WalletPreferenceKeys.mainCurrency) == "USD")
        #expect(converting.string(forKey: WalletPreferenceKeys.legacyHomeCurrency) == nil)
        #expect(converting.string(forKey: WalletPreferenceKeys.legacyDefaultCurrency) == nil)

        let notConverting = freshDefaults()
        notConverting.set("USD", forKey: WalletPreferenceKeys.legacyHomeCurrency)
        notConverting.set("MMK", forKey: WalletPreferenceKeys.legacyDefaultCurrency)
        notConverting.set(false, forKey: WalletPreferenceKeys.convertTotals)
        #expect(CurrencyViewModel(provider: StubRateProvider(set: rates), preferences: notConverting)
            .mainCurrency == "MMK")

        // A home currency never chosen was the region's currency, which converted totals were in.
        let unchosenHome = freshDefaults()
        unchosenHome.set("MMK", forKey: WalletPreferenceKeys.legacyDefaultCurrency)
        unchosenHome.set(true, forKey: WalletPreferenceKeys.convertTotals)
        let region = Locale.current.currency?.identifier ?? "MMK"
        #expect(CurrencyViewModel(provider: StubRateProvider(set: rates), preferences: unchosenHome)
            .mainCurrency == region)
    }

    /// The feed has no MMK: no download is attempted and converted totals stay off, while a
    /// record's own rate still converts.
    @Test func aMainCurrencyOutsideTheFeedSkipsDownloadsButKeepsManualRates() async {
        let model = model(provider: StubRateProvider(set: rates, supported: ["USD", "EUR"]), main: "MMK")
        #expect(!model.hasRatesForMainCurrency)
        await model.refresh(force: true)
        #expect(model.rates == nil)
        #expect(model.errorMessage == nil)
        #expect(!model.isConversionAvailable)
        #expect(model.convert(10, from: "USD", manualRate: 3_000) == 30_000)
    }

    @Test func refreshStoresTheDownloadedSet() async {
        let model = model(provider: StubRateProvider(set: rates))
        await model.refresh(force: true)
        #expect(model.rates != nil)
        #expect(model.errorMessage == nil)
    }

    /// Losing the network must not discard rates already cached.
    @Test func aFailedRefreshKeepsCachedRatesAndExplains() async {
        let model = model(provider: StubRateProvider(error: ExchangeRateError.unavailable), cached: rates)
        await model.refresh(force: true)
        #expect(model.rates != nil)
        #expect(model.isConversionAvailable)
        #expect(model.errorMessage != nil)
    }

    @Test func amountsConvertIntoTheMainCurrency() {
        let model = model(provider: StubRateProvider(set: rates), cached: rates)
        #expect(model.convert(100, from: "USD") == 100)
        #expect(model.convert(90, from: "EUR") == 100)
        #expect(model.convert(100, from: "CHF") == nil) // no rate, no guess
    }

    /// A pinned rate wins over the downloaded one, and works even with no rates at all.
    @Test func aManualRateOverridesTheMarketRate() {
        let online = model(provider: StubRateProvider(set: rates), cached: rates)
        #expect(online.convert(100, from: "EUR", manualRate: Decimal(string: "1.5")!) == 150)

        let offline = model(provider: StubRateProvider(error: ExchangeRateError.unavailable))
        #expect(offline.convert(100, from: "EUR", manualRate: Decimal(string: "1.5")!) == 150)
        #expect(offline.convert(100, from: "EUR") == nil)
    }

    @Test func combinedTotalsRefuseToGuessWhenACurrencyIsMissing() {
        let model = model(provider: StubRateProvider(set: rates), cached: rates)
        #expect(model.total([(100, "USD"), (90, "EUR")]) == 200)
        #expect(model.total([(100, "USD"), (10, "CHF")]) == nil)
    }

    @Test func transferDifferenceReportsGainAndLossInTheMainCurrency() {
        let model = model(provider: StubRateProvider(set: rates), cached: rates)
        // 100 USD out, 90 EUR in = exactly 100 USD: no difference.
        #expect(model.transferDifference(sent: 100, sentCurrency: "USD",
                                         received: 90, receivedCurrency: "EUR") == 0)
        // 100 USD out but only 81 EUR arrived = 90 USD, a 10 USD loss.
        #expect(model.transferDifference(sent: 100, sentCurrency: "USD",
                                         received: 81, receivedCurrency: "EUR") == -10)
        // Same-currency transfers have nothing to report.
        #expect(model.transferDifference(sent: 100, sentCurrency: "USD",
                                         received: 100, receivedCurrency: "USD") == nil)
    }
}

struct ManualRateValidationTests {
    @Test func aPinnedRateMustBePositive() {
        var draft = RecordDraft()
        draft.accountID = UUID()
        draft.amount = 10
        draft.categoryID = UUID()

        draft.manualRate = Decimal(string: "1.25")
        #expect(throws: Never.self) { try draft.validate() }

        draft.manualRate = 0
        #expect(throws: RecordValidationError.invalidRate) { try draft.validate() }

        draft.manualRate = -1
        #expect(throws: RecordValidationError.invalidRate) { try draft.validate() }

        // No override at all remains valid.
        draft.manualRate = nil
        #expect(throws: Never.self) { try draft.validate() }
    }

    /// The pinned rate is a new persisted field, so confirm it survives a save and reload and that
    /// records written without one still load.
    @MainActor
    @Test func pinnedRatesRoundTripThroughStorage() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let accounts = AccountUseCases(repository: repository)
        try await accounts.create(name: "Cash", type: .cash, currencyCode: "EUR",
                                  settings: AccountSettings(currentBalance: 0))
        let account = try #require(try await accounts.load().first)
        let categories = try await CategoryUseCases(repository: repository).load()
        let category = try #require(categories.first { $0.parentID == nil })
        let records = RecordUseCases(repository: repository)

        var pinned = RecordDraft()
        pinned.accountID = account.id
        pinned.categoryID = category.id
        pinned.amount = 20
        pinned.manualRate = Decimal(string: "1.2345")!
        try await records.create(id: UUID(), draft: pinned)

        var plain = pinned
        plain.manualRate = nil
        plain.amount = 30
        try await records.create(id: UUID(), draft: plain)

        let loaded = try await records.load()
        #expect(loaded.count == 2)
        #expect(loaded.first { $0.draft.amount == 20 }?.draft.manualRate == Decimal(string: "1.2345")!)
        #expect(loaded.first { $0.draft.amount == 30 }?.draft.manualRate == nil)
    }
}
