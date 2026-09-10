import Foundation
import WalletDomain
#if canImport(Vision)
    import Vision
#endif

/// What on-device OCR could make out of a receipt.
///
/// Both fields are optional and always presented as a suggestion the user confirms: OCR on a
/// crumpled receipt is a guess, and silently overwriting a typed amount would be worse than
/// offering nothing.
public struct ReceiptReading: Sendable, Equatable {
    public var amount: Decimal?
    public var date: Date?

    public var isEmpty: Bool { amount == nil && date == nil }

    public init(amount: Decimal? = nil, date: Date? = nil) {
        self.amount = amount
        self.date = date
    }
}

/// Extracts a total and a date from receipt text.
public enum ReceiptTextReader {
    /// Lines mentioning one of these are strongly preferred as the total.
    private static let totalKeywords = ["total", "amount due", "balance due", "grand total",
                                        "to pay", "amount", "sum"]
    /// …and these are explicitly not the total.
    private static let excludedKeywords = ["subtotal", "sub total", "tax", "vat", "change",
                                           "cash", "tip", "discount", "savings"]

    #if canImport(Vision)
        /// Runs OCR over a page and interprets the result.
        public static func read(imageData: Data) async -> ReceiptReading {
            await withCheckedContinuation { continuation in
                guard let image = CGImageFromData(imageData) else {
                    continuation.resume(returning: ReceiptReading())
                    return
                }
                let request = VNRecognizeTextRequest { request, _ in
                    let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: interpret(lines: lines))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                } catch {
                    continuation.resume(returning: ReceiptReading())
                }
            }
        }

        private static func CGImageFromData(_ data: Data) -> CGImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    #else
        public static func read(imageData: Data) async -> ReceiptReading { ReceiptReading() }
    #endif

    /// Pure interpretation of already-recognized lines, so the rules are testable without Vision.
    public static func interpret(lines: [String]) -> ReceiptReading {
        ReceiptReading(amount: amount(in: lines), date: date(in: lines))
    }

    /// Prefers a line that names a total, ignores subtotals and taxes, and otherwise falls back to
    /// the largest amount on the receipt — which is nearly always the total.
    public static func amount(in lines: [String]) -> Decimal? {
        var keyed: [Decimal] = []
        var all: [Decimal] = []
        for line in lines {
            let lower = line.lowercased()
            let values = amounts(in: line)
            guard !values.isEmpty else { continue }
            all.append(contentsOf: values)
            guard !excludedKeywords.contains(where: lower.contains) else { continue }
            if totalKeywords.contains(where: lower.contains) { keyed.append(contentsOf: values) }
        }
        // Among lines naming a total, the largest is the one that matters.
        if let best = keyed.max() { return best }
        return all.max()
    }

    private static func amounts(in line: String) -> [Decimal] {
        // Group separators may be a space, comma or dot, so both "1,234.56" and "1.234,56" match
        // whole. Requiring the two-decimal tail keeps quantities and phone numbers out.
        let pattern = #"(?<![0-9])[0-9]{1,3}(?:[ ,.][0-9]{3})*(?:[.,][0-9]{2})(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let found = Range(match.range, in: line) else { return nil }
            return normalized(String(line[found]))
        }
    }

    /// Handles both `1,234.56` and `1.234,56`, and spaces used as group separators.
    private static func normalized(_ text: String) -> Decimal? {
        var cleaned = text.replacingOccurrences(of: " ", with: "")
        if let lastComma = cleaned.lastIndex(of: ","), let lastDot = cleaned.lastIndex(of: ".") {
            if lastComma > lastDot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    /// The first date that parses and is not in the future — a receipt cannot be for tomorrow.
    public static func date(in lines: [String], now: Date = Date()) -> Date? {
        let patterns = ["dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yyyy",
                        "dd/MM/yy", "MM/dd/yy", "yyyy/MM/dd"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        let detector = try? NSRegularExpression(
            pattern: #"[0-9]{1,4}[./-][0-9]{1,2}[./-][0-9]{2,4}"#)

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            for match in detector?.matches(in: line, range: range) ?? [] {
                guard let found = Range(match.range, in: line) else { continue }
                let text = String(line[found])
                for pattern in patterns {
                    parser.dateFormat = pattern
                    if let date = parser.date(from: text), date <= now { return date }
                }
            }
        }
        return nil
    }
}
