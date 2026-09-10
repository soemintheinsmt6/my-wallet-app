import Foundation

public enum ExchangeRateError: LocalizedError, Equatable {
    case missingRate(from: String, to: String)
    case invalidRate
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .missingRate(let from, let to): "No exchange rate is available from \(from) to \(to)."
        case .invalidRate: "The exchange rate must be greater than zero."
        case .unavailable: "Exchange rates have not been downloaded yet."
        }
    }
}

/// Rates for one day, quoted against a single base currency.
///
/// `rates[code]` is how many units of `code` one unit of `base` buys, matching how public rate
/// feeds publish them.
public struct ExchangeRateSet: Codable, Sendable, Equatable {
    public let base: String
    /// The day these rates are for, normalized to midnight UTC.
    public let date: Date
    public let rates: [String: Decimal]
    /// When this set was downloaded, used to decide staleness.
    public let fetchedAt: Date

    public init(base: String, date: Date, rates: [String: Decimal], fetchedAt: Date = Date()) {
        self.base = base
        self.date = date
        self.rates = rates
        self.fetchedAt = fetchedAt
    }

    public var currencies: [String] { (rates.keys.map { $0 } + [base]).sorted() }

    public func contains(_ code: String) -> Bool {
        code == base || rates[code] != nil
    }
}

/// Converts amounts between currencies using a rate set.
///
/// Conversion always goes through the set's base as a cross-rate, so a set quoted in EUR can still
/// convert USD to GBP. Rates are `Decimal` throughout: money must not round-trip through `Double`.
public enum CurrencyConverter {
    /// Units of `to` per one unit of `from`.
    public static func rate(from: String, to: String, using set: ExchangeRateSet) throws -> Decimal {
        if from == to { return 1 }
        let fromRate = try rateAgainstBase(from, in: set)
        let toRate = try rateAgainstBase(to, in: set)
        guard fromRate > 0 else { throw ExchangeRateError.invalidRate }
        return toRate / fromRate
    }

    private static func rateAgainstBase(_ code: String, in set: ExchangeRateSet) throws -> Decimal {
        if code == set.base { return 1 }
        guard let rate = set.rates[code], rate > 0 else {
            throw ExchangeRateError.missingRate(from: set.base, to: code)
        }
        return rate
    }

    /// Converts and rounds to the target currency's usual precision.
    public static func convert(_ amount: Decimal, from: String, to: String,
                               using set: ExchangeRateSet) throws -> Decimal {
        guard from != to else { return amount }
        let converted = amount * (try rate(from: from, to: to, using: set))
        return rounded(converted, currencyCode: to)
    }

    /// Converts using an explicit rate, for a record whose rate the user has overridden.
    public static func convert(_ amount: Decimal, to: String, rate: Decimal) throws -> Decimal {
        guard rate > 0 else { throw ExchangeRateError.invalidRate }
        return rounded(amount * rate, currencyCode: to)
    }

    /// Most currencies use two decimals; a few use none. Anything unknown keeps two.
    public static func fractionDigits(for currencyCode: String) -> Int {
        zeroDecimalCurrencies.contains(currencyCode) ? 0 : 2
    }

    public static func rounded(_ amount: Decimal, currencyCode: String) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, fractionDigits(for: currencyCode), .bankers)
        return result
    }

    private static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
        "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF",
    ]
}

/// Fetches rates from a remote feed.
///
/// A protocol so the app can inject a real network client while tests use fixed rates and never
/// touch the network.
public protocol ExchangeRateProviding: Sendable {
    /// Latest rates when `date` is nil, otherwise the rates for that day.
    func rates(base: String, on date: Date?) async throws -> ExchangeRateSet
}

/// Decides when cached rates should be refreshed.
public enum ExchangeRatePolicy {
    /// Published rate feeds update once per weekday, so refreshing more than daily is wasteful.
    public static let refreshInterval: TimeInterval = 6 * 3600

    public static func needsRefresh(_ set: ExchangeRateSet?, now: Date = Date()) -> Bool {
        guard let set else { return true }
        let age = now.timeIntervalSince(set.fetchedAt)
        // A clock that moved backwards should refresh rather than trust the cache indefinitely.
        return age < 0 || age >= refreshInterval
    }
}
