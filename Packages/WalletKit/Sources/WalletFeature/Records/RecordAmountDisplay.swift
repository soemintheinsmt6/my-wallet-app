import Foundation

enum RecordAmountDisplay {
    /// The grouped form of a stored amount, for read-only text. Editable fields group through
    /// `Binding.groupedAmount()` instead, which keeps the plain digits in state.
    static func grouped(_ amount: Decimal, locale: Locale = .current) -> String {
        grouped(AccountAmountInput.text(amount, locale: locale), locale: locale)
    }

    /// Group only the display; preserve the editable decimal and trailing zeros exactly.
    static func grouped(_ input: String, locale: Locale = .current) -> String {
        guard !input.isEmpty else { return "0" }
        let decimal = locale.decimalSeparator ?? "."
        // A balance or an adjustment can be negative, so the sign is set aside and put back rather
        // than failing the digit check below and leaving the number ungrouped.
        var sign = ""
        var body = input
        if let first = body.first, first == "-" || first == "+" {
            sign = String(first)
            body = String(body.dropFirst())
        }
        let parts = body.components(separatedBy: decimal)
        guard parts.count <= 2, let integer = parts.first,
              !integer.isEmpty, integer.allSatisfy({ $0.isASCII && $0.isNumber }),
              parts.dropFirst().allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return input }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let primary = formatter.groupingSize
        guard primary > 0 else { return input }
        let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary
        var remaining = integer[...]
        var groups: [String] = []
        var size = primary
        while remaining.count > size {
            groups.append(String(remaining.suffix(size)))
            remaining = remaining.dropLast(size)
            size = secondary
        }
        groups.append(String(remaining))
        let grouped = groups.reversed().joined(separator: formatter.groupingSeparator ?? ",")
        return sign + (parts.count == 2 ? grouped + decimal + parts[1] : grouped)
    }

    /// The inverse of `grouped`: strips the separators a field displays so the stored text stays in
    /// the plain form `AccountAmountInput.parse` reads. Anything else is left alone, so invalid
    /// input still reaches the parser and is still reported.
    static func ungrouped(_ input: String, locale: Locale = .current) -> String {
        // Narrow and non-breaking spaces group digits in several locales, and either can arrive
        // from a paste even where the locale separator is something else.
        let separators = [locale.groupingSeparator, "\u{202F}", "\u{00A0}", " "].compactMap { $0 }
        return separators.reduce(input) { $0.replacingOccurrences(of: $1, with: "") }
    }
}
