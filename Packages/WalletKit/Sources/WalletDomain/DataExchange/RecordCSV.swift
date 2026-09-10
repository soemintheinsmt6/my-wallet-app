import Foundation

/// The columns of the record CSV, in export order.
///
/// Import matches on these names but does not require this order or every column, so a file
/// exported from a spreadsheet with reordered or missing optional columns still loads.
public enum RecordCSVColumn: String, CaseIterable, Sendable, Identifiable {
    case date = "Date"
    case type = "Type"
    case amount = "Amount"
    case currency = "Currency"
    case account = "Account"
    case toAccount = "To Account"
    case category = "Category"
    case labels = "Labels"
    case payee = "Payee"
    case note = "Note"
    case paymentType = "Payment Type"

    public var id: String { rawValue }

    /// A row cannot become a record without these.
    public var isRequired: Bool {
        switch self {
        case .date, .type, .amount, .account: true
        default: false
        }
    }
}

/// One CSV row resolved into plain values, before it is matched against the wallet's own
/// accounts and categories.
public struct RecordCSVRow: Sendable, Equatable {
    public var date: Date
    public var kind: RecordKind
    public var amount: Decimal
    public var currencyCode: String
    public var accountName: String
    public var destinationAccountName: String
    public var categoryPath: String
    public var labelNames: [String]
    public var payee: String
    public var note: String
    public var paymentType: PaymentType

    public init(date: Date, kind: RecordKind, amount: Decimal, currencyCode: String = "",
                accountName: String, destinationAccountName: String = "", categoryPath: String = "",
                labelNames: [String] = [], payee: String = "", note: String = "",
                paymentType: PaymentType = .unspecified) {
        self.date = date
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.accountName = accountName
        self.destinationAccountName = destinationAccountName
        self.categoryPath = categoryPath
        self.labelNames = labelNames
        self.payee = payee
        self.note = note
        self.paymentType = paymentType
    }
}

public enum RecordCSVError: LocalizedError, Equatable {
    case missingColumns([RecordCSVColumn])
    case invalidDate(row: Int, value: String)
    case invalidType(row: Int, value: String)
    case invalidAmount(row: Int, value: String)
    case missingAccount(row: Int)

    public var errorDescription: String? {
        switch self {
        case .missingColumns(let columns):
            "The file is missing required columns: \(columns.map(\.rawValue).joined(separator: ", "))."
        case .invalidDate(let row, let value): "Row \(row): “\(value)” is not a date this app can read."
        case .invalidType(let row, let value): "Row \(row): “\(value)” is not expense, income or transfer."
        case .invalidAmount(let row, let value): "Row \(row): “\(value)” is not a positive amount."
        case .missingAccount(let row): "Row \(row): the account name is empty."
        }
    }
}

/// Turns records into CSV rows and back.
///
/// Amounts are written unsigned with the type carrying the direction, matching how they are
/// stored; labels are semicolon-separated so a comma never has to be escaped inside a field.
public enum RecordCSV {
    public static let labelSeparator = "; "
    public static let categorySeparator = " / "

    private static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    public static func export(records: [WalletRecord], accounts: [Account],
                              categories: [WalletCategory], tags: [WalletTag]) -> String {
        let accountsByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tagsByID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var rows: [[String]] = [RecordCSVColumn.allCases.map(\.rawValue)]
        for record in records.sorted(by: { $0.draft.date < $1.draft.date }) {
            let draft = record.draft
            let labels = draft.tagIDs.compactMap { tagsByID[$0]?.name }.sorted()
            rows.append([
                formatter.string(from: draft.date),
                draft.kind.rawValue,
                string(from: draft.amount),
                record.currencyCode,
                draft.accountID.flatMap { accountsByID[$0]?.name } ?? "",
                draft.destinationAccountID.flatMap { accountsByID[$0]?.name } ?? "",
                path(for: draft.categoryID, in: categoriesByID),
                labels.joined(separator: labelSeparator),
                draft.payee,
                draft.note,
                draft.paymentType.rawValue,
            ])
        }
        return CSV.encode(rows: rows)
    }

    public static func path(for id: UUID?, in categories: [UUID: WalletCategory]) -> String {
        guard let id, let category = categories[id] else { return "" }
        guard let parent = category.parentID.flatMap({ categories[$0] }) else { return category.name }
        return "\(parent.name)\(categorySeparator)\(category.name)"
    }

    /// Exact decimal text, never a rounded double.
    public static func string(from amount: Decimal) -> String {
        var value = amount
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Import

    /// Maps header names to columns. Comparison ignores case and surrounding whitespace so files
    /// touched by a spreadsheet still line up.
    public static func mapping(header: [String]) -> [RecordCSVColumn: Int] {
        var mapping: [RecordCSVColumn: Int] = [:]
        for (index, raw) in header.enumerated() {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let column = RecordCSVColumn.allCases.first(where: { $0.rawValue.lowercased() == name }),
               mapping[column] == nil {
                mapping[column] = index
            }
        }
        return mapping
    }

    /// Parses rows using an explicit column mapping, so a caller can correct the mapping first.
    public static func rows(from table: [[String]], mapping: [RecordCSVColumn: Int]) throws -> [RecordCSVRow] {
        let missing = RecordCSVColumn.allCases.filter { $0.isRequired && mapping[$0] == nil }
        guard missing.isEmpty else { throw RecordCSVError.missingColumns(missing) }

        return try table.dropFirst().enumerated().compactMap { offset, columns in
            // Header is row 1, so the first body row reads as row 2 in any spreadsheet.
            let number = offset + 2
            func value(_ column: RecordCSVColumn) -> String {
                guard let index = mapping[column], index < columns.count else { return "" }
                return columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Skip rows that are entirely empty rather than failing the whole import.
            guard columns.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return nil
            }

            let rawDate = value(.date)
            guard let date = date(from: rawDate) else {
                throw RecordCSVError.invalidDate(row: number, value: rawDate)
            }
            let rawType = value(.type).lowercased()
            guard let kind = RecordKind(rawValue: rawType) else {
                throw RecordCSVError.invalidType(row: number, value: value(.type))
            }
            let rawAmount = value(.amount)
            guard let amount = decimal(from: rawAmount), amount > 0 else {
                throw RecordCSVError.invalidAmount(row: number, value: rawAmount)
            }
            let account = value(.account)
            guard !account.isEmpty else { throw RecordCSVError.missingAccount(row: number) }

            let labels = value(.labels)
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return RecordCSVRow(date: date, kind: kind, amount: amount, currencyCode: value(.currency),
                                accountName: account, destinationAccountName: value(.toAccount),
                                categoryPath: value(.category), labelNames: labels,
                                payee: value(.payee), note: value(.note),
                                paymentType: paymentType(from: value(.paymentType)))
        }
    }

    /// Payment-type raw values are camelCase, so match case-insensitively rather than lowercasing
    /// the text and hoping it equals the raw value.
    public static func paymentType(from text: String) -> PaymentType {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return .unspecified }
        return PaymentType.allCases.first { $0.rawValue.lowercased() == name } ?? .unspecified
    }

    /// Accepts the ISO form this app writes, plus the plain date and common spreadsheet renderings.
    public static func date(from text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        if let date = formatter.date(from: text) { return date }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let patterns = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
                        "yyyy/MM/dd HH:mm", "yyyy/MM/dd", "MM/dd/yyyy HH:mm", "MM/dd/yyyy",
                        "dd/MM/yyyy HH:mm", "dd/MM/yyyy"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        for pattern in patterns {
            parser.dateFormat = pattern
            if let date = parser.date(from: text) { return date }
        }
        return nil
    }

    /// Parses an amount written with either decimal separator, ignoring grouping and currency
    /// symbols a spreadsheet may have added.
    public static func decimal(from text: String) -> Decimal? {
        guard !text.isEmpty else { return nil }
        var cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        // "1.234,56" is comma-decimal; "1,234.56" is comma-grouping.
        if let lastComma = cleaned.lastIndex(of: ","), let lastDot = cleaned.lastIndex(of: ".") {
            if lastComma > lastDot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if cleaned.contains(",") {
            // A single comma is a decimal separator unless it groups exactly three digits.
            let parts = cleaned.split(separator: ",", omittingEmptySubsequences: false)
            cleaned = parts.count == 2 && parts[1].count == 3
                ? parts.joined()
                : cleaned.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}
