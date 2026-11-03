import Foundation

/// How large amounts are counted where space is tight, such as the total inside a donut chart.
public enum NumberScale: String, CaseIterable, Identifiable {
    /// Lakhs for currencies usually read that way (MMK, INR…), millions for the rest.
    case automatic
    /// Lakhs (100,000) for every currency.
    case lakhs
    /// Thousands, millions and billions (K, M, B) for every currency.
    case millions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .lakhs: "Lakhs"
        case .millions: "Millions"
        }
    }

    /// Currencies whose amounts are usually read in lakhs.
    static let lakhCurrencies: Set<String> = ["MMK", "INR", "PKR", "BDT", "NPR", "LKR"]

    func usesLakhs(for currencyCode: String) -> Bool {
        switch self {
        case .automatic: Self.lakhCurrencies.contains(currencyCode)
        case .lakhs: true
        case .millions: false
        }
    }
}
