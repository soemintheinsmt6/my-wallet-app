import Combine
import Foundation
import WalletDomain

/// Owns the main currency and the rates used to convert into it.
///
/// The main currency is where new items start, which currency summaries open in, and what
/// converted totals are expressed in. Conversion is opt-in: until it is turned on, or while no rates
/// are downloaded, every screen keeps showing per-currency totals exactly as before. Converted
/// figures are always labelled as estimates, because a single daily rate is not what the bank
/// actually charged.
@MainActor
public final class CurrencyViewModel: ObservableObject {
    @Published public private(set) var rates: ExchangeRateSet?
    @Published public private(set) var isRefreshing = false
    @Published public var errorMessage: String?

    @Published public var mainCurrency: String {
        didSet {
            guard mainCurrency != oldValue else { return }
            preferences.set(mainCurrency, forKey: WalletPreferenceKeys.mainCurrency)
            errorMessage = nil
            Task { await refresh(force: true) }
        }
    }

    public static let fallbackMainCurrency = "MMK"

    @Published public var convertsTotals: Bool {
        didSet {
            guard convertsTotals != oldValue else { return }
            preferences.set(convertsTotals, forKey: WalletPreferenceKeys.convertTotals)
        }
    }

    private let provider: any ExchangeRateProviding
    private let preferences: UserDefaults
    private let load: () -> ExchangeRateSet?
    private let store: (ExchangeRateSet) -> Void

    public init(provider: any ExchangeRateProviding,
                preferences: UserDefaults = .standard,
                load: @escaping () -> ExchangeRateSet? = { nil },
                store: @escaping (ExchangeRateSet) -> Void = { _ in }) {
        self.provider = provider
        self.preferences = preferences
        self.load = load
        self.store = store
        let converts = preferences.object(forKey: WalletPreferenceKeys.convertTotals) as? Bool ?? false
        convertsTotals = converts
        mainCurrency = Self.migratedMainCurrency(preferences, convertsTotals: converts)
        rates = load()
    }

    /// Builds before 2026-11 kept a home currency (for conversion) and a default currency (for new
    /// items). Someone converting totals keeps the currency those totals are shown in; anyone else
    /// keeps the one their new items start in. The old keys are removed once carried over.
    private static func migratedMainCurrency(_ preferences: UserDefaults, convertsTotals: Bool) -> String {
        if let main = preferences.string(forKey: WalletPreferenceKeys.mainCurrency) { return main }
        let legacyDefault = preferences.string(forKey: WalletPreferenceKeys.legacyDefaultCurrency)
        // An unchosen home currency was never saved and fell back to the region's currency.
        let home = preferences.string(forKey: WalletPreferenceKeys.legacyHomeCurrency)
            ?? (convertsTotals ? Locale.current.currency?.identifier : nil)
        let main = (convertsTotals ? home ?? legacyDefault : legacyDefault ?? home) ?? fallbackMainCurrency
        if home != nil || legacyDefault != nil {
            preferences.set(main, forKey: WalletPreferenceKeys.mainCurrency)
            preferences.removeObject(forKey: WalletPreferenceKeys.legacyHomeCurrency)
            preferences.removeObject(forKey: WalletPreferenceKeys.legacyDefaultCurrency)
        }
        return main
    }

    /// False when the rate feed does not publish the main currency, so nothing can be converted
    /// into it automatically. Records with their own manual rate still convert.
    public var hasRatesForMainCurrency: Bool {
        provider.supportedCurrencies?.contains(mainCurrency) ?? true
    }

    /// True only when converted totals can actually be shown.
    public var isConversionAvailable: Bool { convertsTotals && rates != nil && hasRatesForMainCurrency }

    public var lastUpdated: Date? { rates?.fetchedAt }

    /// Refreshes rates when the cache is stale, or always when `force` is set.
    public func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        // The feed would reject this base; settings explain why there are no converted totals.
        guard hasRatesForMainCurrency else { return }
        guard force || ExchangeRatePolicy.needsRefresh(rates) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let set = try await provider.rates(base: mainCurrency, on: nil)
            rates = set
            store(set)
            errorMessage = nil
        } catch {
            // Keep whatever is cached; conversion simply stays on the older rates.
            errorMessage = rates == nil
                ? "Exchange rates could not be downloaded. Totals stay separate per currency."
                : "Exchange rates could not be refreshed. Showing rates from \(rates!.fetchedAt.formatted(date: .abbreviated, time: .shortened))."
        }
    }

    /// Converts into the main currency, honoring a record's pinned rate when it has one.
    ///
    /// Returns `nil` rather than a wrong number when no rate is available.
    public func convert(_ amount: Decimal, from currency: String, manualRate: Decimal? = nil) -> Decimal? {
        if currency == mainCurrency { return amount }
        if let manualRate, manualRate > 0 {
            return try? CurrencyConverter.convert(amount, to: mainCurrency, rate: manualRate)
        }
        guard let rates else { return nil }
        return try? CurrencyConverter.convert(amount, from: currency, to: mainCurrency, using: rates)
    }

    /// Sums amounts already grouped by currency, or `nil` when any currency cannot be converted.
    public func total(_ amounts: [(amount: Decimal, currency: String)]) -> Decimal? {
        var total = Decimal.zero
        for entry in amounts {
            guard let converted = convert(entry.amount, from: entry.currency) else { return nil }
            total += converted
        }
        return CurrencyConverter.rounded(total, currencyCode: mainCurrency)
    }

    public var availableCurrencies: [String] {
        guard let rates else { return Locale.commonISOCurrencyCodes }
        return rates.currencies
    }

    /// What a cross-currency transfer gained or lost, in the main currency.
    ///
    /// Positive means more arrived than left. Returns `nil` when either leg cannot be converted.
    public func transferDifference(sent: Decimal, sentCurrency: String,
                                   received: Decimal, receivedCurrency: String) -> Decimal? {
        guard sentCurrency != receivedCurrency,
              let out = convert(sent, from: sentCurrency),
              let into = convert(received, from: receivedCurrency) else { return nil }
        return CurrencyConverter.rounded(into - out, currencyCode: mainCurrency)
    }
}
