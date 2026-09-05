import Foundation

enum RecordAmountDisplay {
    /// Group only the display; preserve the editable decimal and trailing zeros exactly.
    static func grouped(_ input: String, locale: Locale = .current) -> String {
        guard !input.isEmpty else { return "0" }
        let decimal = locale.decimalSeparator ?? "."
        let parts = input.components(separatedBy: decimal)
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
        return parts.count == 2 ? grouped + decimal + parts[1] : grouped
    }
}
