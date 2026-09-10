import Foundation
import WalletDomain

/// Downloads rates from Frankfurter, a free ECB-backed feed that needs no API key.
///
/// The endpoint answers both the latest rates and any historical day, which is what accurate
/// conversion of past records needs. Rates are decoded from their JSON number text rather than
/// through `Double`, so no precision is lost before the `Decimal` arithmetic.
public struct FrankfurterExchangeRateProvider: ExchangeRateProviding {
    private let session: URLSession
    private let host: URL

    public init(session: URLSession = .shared,
                host: URL = URL(string: "https://api.frankfurter.app")!) {
        self.session = session
        self.host = host
    }

    public func rates(base: String, on date: Date?) async throws -> ExchangeRateSet {
        var components = URLComponents(url: host.appendingPathComponent(path(for: date)),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "from", value: base)]
        guard let url = components?.url else { throw ExchangeRateError.unavailable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExchangeRateError.unavailable
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let day = DayFormatter.date(from: payload.date) ?? Date()
        return ExchangeRateSet(base: payload.base, date: day,
                               rates: payload.rates.mapValues(\.value), fetchedAt: Date())
    }

    private func path(for date: Date?) -> String {
        guard let date else { return "latest" }
        return DayFormatter.string(from: date)
    }

    private struct Payload: Decodable {
        let base: String
        let date: String
        let rates: [String: DecimalValue]
    }

    /// Decodes a JSON number without going through `Double`.
    private struct DecimalValue: Decodable {
        let value: Decimal

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self),
               let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
                value = decimal
                return
            }
            let double = try container.decode(Double.self)
            value = Decimal(string: String(double), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(double)
        }
    }
}

enum DayFormatter {
    /// Plain `yyyy-MM-dd` in UTC, the form the feed uses for a day.
    ///
    /// Built per call rather than shared: `ISO8601DateFormatter` is not `Sendable`, and rate
    /// requests are rare enough that the allocation does not matter.
    static func make() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    static func string(from date: Date) -> String { make().string(from: date) }
    static func date(from text: String) -> Date? { make().date(from: text) }
}

/// Caches the most recent rate set on disk so conversion keeps working offline.
public struct ExchangeRateCache: Sendable {
    private let url: URL

    public init(fileName: String = "exchange-rates.json") {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent(fileName, isDirectory: false)
    }

    public func load() -> ExchangeRateSet? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ExchangeRateSet.self, from: data)
    }

    public func save(_ set: ExchangeRateSet) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(set) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
