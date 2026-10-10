import Combine
import Foundation
import WalletDomain

/// Owns the home currency and the rates used to convert into it.
///
/// Conversion is opt-in: with no home currency chosen, or no rates downloaded, every screen keeps
/// showing per-currency totals exactly as before. Converted figures are always labelled as
/// estimates, because a single daily rate is not what the bank actually charged.
@MainActor
public final class CurrencyViewModel: ObservableObject {
    @Published public private(set) var rates: ExchangeRateSet?
    @Published public private(set) var isRefreshing = false
    @Published public var errorMessage: String?

    @Published public var homeCurrency: String {
        didSet {
            guard homeCurrency != oldValue else { return }
            preferences.set(homeCurrency, forKey: WalletPreferenceKeys.homeCurrency)
            Task { await refresh(force: true) }
        }
    }

    /// The currency new items start in. Separate from the home currency, which drives conversion
    /// and must be one the rate feed publishes.
    @Published public var defaultCurrency: String {
        didSet {
            guard defaultCurrency != oldValue else { return }
            preferences.set(defaultCurrency, forKey: WalletPreferenceKeys.defaultCurrency)
        }
    }

    public static let fallbackDefaultCurrency = "MMK"

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
        homeCurrency = preferences.string(forKey: WalletPreferenceKeys.homeCurrency)
            ?? Locale.current.currency?.identifier ?? "USD"
        defaultCurrency = preferences.string(forKey: WalletPreferenceKeys.defaultCurrency) ?? Self.fallbackDefaultCurrency
        convertsTotals = preferences.object(forKey: WalletPreferenceKeys.convertTotals) as? Bool ?? false
        rates = load()
    }

    /// True only when converted totals can actually be shown.
    public var isConversionAvailable: Bool { convertsTotals && rates != nil }

    public var lastUpdated: Date? { rates?.fetchedAt }

    /// Refreshes rates when the cache is stale, or always when `force` is set.
    public func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        guard force || ExchangeRatePolicy.needsRefresh(rates) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let set = try await provider.rates(base: homeCurrency, on: nil)
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

    /// Converts into the home currency, honoring a record's pinned rate when it has one.
    ///
    /// Returns `nil` rather than a wrong number when no rate is available.
    public func convert(_ amount: Decimal, from currency: String, manualRate: Decimal? = nil) -> Decimal? {
        if currency == homeCurrency { return amount }
        if let manualRate, manualRate > 0 {
            return try? CurrencyConverter.convert(amount, to: homeCurrency, rate: manualRate)
        }
        guard let rates else { return nil }
        return try? CurrencyConverter.convert(amount, from: currency, to: homeCurrency, using: rates)
    }

    /// Sums amounts already grouped by currency, or `nil` when any currency cannot be converted.
    public func total(_ amounts: [(amount: Decimal, currency: String)]) -> Decimal? {
        var total = Decimal.zero
        for entry in amounts {
            guard let converted = convert(entry.amount, from: entry.currency) else { return nil }
            total += converted
        }
        return CurrencyConverter.rounded(total, currencyCode: homeCurrency)
    }

    public var availableCurrencies: [String] {
        guard let rates else { return Locale.commonISOCurrencyCodes }
        return rates.currencies
    }

    /// What a cross-currency transfer gained or lost, in the home currency.
    ///
    /// Positive means more arrived than left. Returns `nil` when either leg cannot be converted.
    public func transferDifference(sent: Decimal, sentCurrency: String,
                                   received: Decimal, receivedCurrency: String) -> Decimal? {
        guard sentCurrency != receivedCurrency,
              let out = convert(sent, from: sentCurrency),
              let into = convert(received, from: receivedCurrency) else { return nil }
        return CurrencyConverter.rounded(into - out, currencyCode: homeCurrency)
    }
}
