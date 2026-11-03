import Foundation

/// How large amounts are counted where space is tight: chart totals and axes, small widgets and
/// watch complications.
///
/// Lives in the domain so the widget and watch extensions, which receive it in `WalletSnapshot`,
/// count amounts the same way as the app.
public enum NumberScale: String, CaseIterable, Identifiable, Codable, Sendable {
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
    public static let lakhCurrencies: Set<String> = ["MMK", "INR", "PKR", "BDT", "NPR", "LKR"]

    public func usesLakhs(for currencyCode: String) -> Bool {
        switch self {
        case .automatic: Self.lakhCurrencies.contains(currencyCode)
        case .lakhs: true
        case .millions: false
        }
    }
}

extension Decimal {
    /// Compact money for widgets and complications, e.g. "$12.5K", or "MMK 52.7L" when the scale
    /// counts this currency in lakhs. Amounts under one lakh always use the K form.
    /// Compact currency notation needs the newer OS releases the widget and watch targets run on.
    @available(iOS 18, macOS 15, watchOS 11, visionOS 2, *)
    public func compactCurrency(_ currencyCode: String, scale: NumberScale) -> String {
        if scale.usesLakhs(for: currencyCode), abs(self) >= 100_000 {
            let lakhs = self / 100_000
            var text = lakhs.formatted(.currency(code: currencyCode).precision(.fractionLength(0...1)).attributed)
            // The "L" belongs to the digits, wherever the locale puts the currency: "$52.7L", "52.7L US$".
            if let digits = text.runs.last(where: { $0.numberPart != nil }) {
                text.insert(AttributedString("L"), at: digits.range.upperBound)
            } else {
                text.append(AttributedString("L"))
            }
            return String(text.characters)
        }
        return formatted(.currency(code: currencyCode).notation(.compactName).precision(.fractionLength(0...1)))
    }
}
