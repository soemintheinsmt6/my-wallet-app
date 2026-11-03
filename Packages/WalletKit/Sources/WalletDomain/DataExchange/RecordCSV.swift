import Foundation

/// The columns import understands.
///
/// Import matches on these names, or on the common bank-statement names in `aliases`, and does
/// not require any order, so a bank export or a reordered spreadsheet still loads.
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
    /// Bank-statement money out. Never exported.
    case debit = "Debit"
    /// Bank-statement money in. Never exported.
    case credit = "Credit"

    public var id: String { rawValue }

    /// How a missing column is named in an error; Debit and Credit can stand in for Amount.
    var requirementName: String { self == .amount ? "Amount (or Debit and Credit)" : rawValue }

    /// The columns the app writes, in order. Debit and Credit exist only to read bank statements.
    public static let exported: [RecordCSVColumn] = [
        .date, .type, .amount, .currency, .account, .toAccount, .category, .labels, .payee, .note, .paymentType,
    ]

    /// Lowercased header names banks use for this column, most specific first.
    public var aliases: [String] {
        switch self {
        case .date: ["transaction date", "trans. date", "trans date", "posting date", "posted date",
                     "booking date", "value date", "txn date"]
        case .type: ["transaction type", "debit/credit", "dr/cr", "cr/dr"]
        case .amount: ["transaction amount", "amount (signed)", "net amount"]
        case .currency: ["currency code", "ccy"]
        case .payee: ["description", "transaction description", "merchant", "merchant name", "payee name",
                      "name", "details", "narrative", "counterparty"]
        case .note: ["memo", "notes", "remarks", "particulars"]
        case .debit: ["debit amount", "debits", "withdrawal", "withdrawals", "withdrawal amount",
                      "money out", "paid out", "out"]
        case .credit: ["credit amount", "credits", "deposit", "deposits", "deposit amount",
                       "money in", "paid in", "in"]
        case .account, .toAccount, .category, .labels, .paymentType: []
        }
    }
}

/// Choices the person makes for a file that does not fully describe itself, as bank statements
/// usually do not.
public struct RecordCSVImportOptions: Sendable, Equatable {
    /// Used when the file has no Account column or a row leaves it empty.
    public var defaultAccountName: String
    /// Flips signed amounts, for statements (often credit cards) that list spending as positive.
    /// Rows whose Type states the direction (expense, income, debit, credit…) are never flipped.
    public var reversesSigns: Bool

    public init(defaultAccountName: String = "", reversesSigns: Bool = false) {
        self.defaultAccountName = defaultAccountName
        self.reversesSigns = reversesSigns
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
    /// A balance adjustment: `kind` is `.income` for an increase and `.expense` for a decrease.
    public var isAdjustment: Bool
    /// The file gave a day but no time, as bank statements do. Two identical purchases on one
    /// day are then legitimately indistinguishable, which duplicate detection has to allow for.
    public var isDateOnly: Bool

    public init(date: Date, kind: RecordKind, amount: Decimal, currencyCode: String = "",
                accountName: String, destinationAccountName: String = "", categoryPath: String = "",
                labelNames: [String] = [], payee: String = "", note: String = "",
                paymentType: PaymentType = .unspecified, isAdjustment: Bool = false, isDateOnly: Bool = false) {
        self.date = date
        self.kind = kind
        self.isAdjustment = isAdjustment
        self.isDateOnly = isDateOnly
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
            "The file is missing required columns: \(columns.map(\.requirementName).joined(separator: ", "))."
        case .invalidDate(let row, let value): "Row \(row): “\(value)” is not a date this app can read."
        case .invalidType(let row, let value):
            "Row \(row): “\(value)” is not expense, income, transfer, \(RecordCSV.adjustmentIncrease) or \(RecordCSV.adjustmentDecrease)."
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
    /// Type-column values for balance adjustments, which have no record kind of their own.
    public static let adjustmentIncrease = "adjustment increase"
    public static let adjustmentDecrease = "adjustment decrease"

    static func typeText(for draft: RecordDraft) -> String {
        guard draft.isAdjustment else { return draft.kind.rawValue }
        return draft.kind == .income ? adjustmentIncrease : adjustmentDecrease
    }

    /// The kind and adjustment flag a Type value names, or `nil` when it names neither.
    static func type(from text: String) -> (kind: RecordKind, isAdjustment: Bool)? {
        if let kind = RecordKind(rawValue: text) { return (kind, false) }
        // Accept "adjustment-increase" or "adjustment_increase" too, as spreadsheets rewrite them.
        let spaced = text.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        switch spaced {
        case adjustmentIncrease: return (.income, true)
        case adjustmentDecrease: return (.expense, true)
        default: return nil
        }
    }

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

        var rows: [[String]] = [RecordCSVColumn.exported.map(\.rawValue)]
        for record in records.sorted(by: { $0.draft.date < $1.draft.date }) {
            let draft = record.draft
            let labels = draft.tagIDs.compactMap { tagsByID[$0]?.name }.sorted()
            rows.append([
                formatter.string(from: draft.date),
                typeText(for: draft),
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
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var mapping: [RecordCSVColumn: Int] = [:]
        var claimed = Set<Int>()
        // The app's own names win over aliases, so a file with both "Date" and "Posting Date" reads "Date".
        for column in RecordCSVColumn.allCases {
            if let index = names.firstIndex(of: column.rawValue.lowercased()), claimed.insert(index).inserted {
                mapping[column] = index
            }
        }
        for column in RecordCSVColumn.allCases where mapping[column] == nil {
            for alias in column.aliases {
                if let index = names.firstIndex(of: alias), claimed.insert(index).inserted {
                    mapping[column] = index
                    break
                }
            }
        }
        return mapping
    }

    /// The columns a file still needs. An Account column can be replaced by a chosen account,
    /// and Amount by Debit or Credit.
    public static func missingColumns(in mapping: [RecordCSVColumn: Int],
                                      options: RecordCSVImportOptions = RecordCSVImportOptions()) -> [RecordCSVColumn] {
        var missing: [RecordCSVColumn] = []
        if mapping[.date] == nil { missing.append(.date) }
        if mapping[.amount] == nil, mapping[.debit] == nil, mapping[.credit] == nil { missing.append(.amount) }
        if mapping[.account] == nil, options.defaultAccountName.isEmpty { missing.append(.account) }
        return missing
    }

    /// Parses rows using an explicit column mapping, so a caller can correct the mapping first.
    ///
    /// A row's direction comes from its Type when that names an app type (expense, income,
    /// transfer, adjustment) or a bank one (debit, credit). Otherwise it comes from the money:
    /// a Debit value or negative Amount is an expense, a Credit value or positive Amount income.
    public static func rows(from table: [[String]], mapping: [RecordCSVColumn: Int],
                            options: RecordCSVImportOptions = RecordCSVImportOptions()) throws -> [RecordCSVRow] {
        let missing = missingColumns(in: mapping, options: options)
        guard missing.isEmpty else { throw RecordCSVError.missingColumns(missing) }

        let body = Array(table.dropFirst())
        func cell(_ columns: [String], _ column: RecordCSVColumn) -> String {
            guard let index = mapping[column], index < columns.count else { return "" }
            return columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // "03/04/2024" is ambiguous on its own; one "13/04/2024" elsewhere settles the whole file.
        let dayFirst = prefersDayFirst(body.map { cell($0, .date) })
        // A file that states direction by sign may carry Type values of its own ("Sale", "POS"),
        // which are then not errors. The app's own export never has signed amounts.
        let isSigned = mapping[.debit] != nil || mapping[.credit] != nil
            || body.contains { (decimal(from: cell($0, .amount)) ?? 0) < 0 }

        return try body.enumerated().compactMap { offset, columns in
            // Header is row 1, so the first body row reads as row 2 in any spreadsheet.
            let number = offset + 2
            func value(_ column: RecordCSVColumn) -> String { cell(columns, column) }
            // Skip rows that are entirely empty rather than failing the whole import.
            guard columns.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return nil
            }

            let rawDate = value(.date)
            guard let (date, isDateOnly) = parsedDate(from: rawDate, dayFirst: dayFirst) else {
                throw RecordCSVError.invalidDate(row: number, value: rawDate)
            }
            let (kind, isAdjustment, amount) = try direction(
                type: value(.type), hasTypeColumn: mapping[.type] != nil, isSigned: isSigned,
                amount: value(.amount), debit: value(.debit), credit: value(.credit),
                reversesSigns: options.reversesSigns, row: number)
            var account = value(.account)
            if account.isEmpty { account = options.defaultAccountName }
            guard !account.isEmpty else { throw RecordCSVError.missingAccount(row: number) }

            let labels = value(.labels)
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return RecordCSVRow(date: date, kind: kind, amount: amount, currencyCode: value(.currency),
                                accountName: account, destinationAccountName: value(.toAccount),
                                categoryPath: value(.category), labelNames: labels,
                                payee: value(.payee), note: value(.note),
                                paymentType: paymentType(from: value(.paymentType)),
                                isAdjustment: isAdjustment, isDateOnly: isDateOnly)
        }
    }

    /// Bank Type values that say which way money moved.
    static func bankKind(from text: String) -> RecordKind? {
        switch text {
        case "debit", "dr", "withdrawal", "money out": .expense
        case "credit", "cr", "deposit", "money in": .income
        default: nil
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func direction(type rawType: String, hasTypeColumn: Bool, isSigned: Bool,
                                  amount rawAmount: String, debit: String, credit: String,
                                  reversesSigns: Bool, row: Int) throws -> (RecordKind, Bool, Decimal) {
        let typeText = rawType.lowercased()
        // The first non-zero figure, signed: Debit is money out, Credit money in, Amount carries its own sign.
        let signed = [decimal(from: rawAmount),
                      decimal(from: debit).map { -abs($0) },
                      decimal(from: credit).map { abs($0) }]
            .compactMap { $0 }
            .first { $0 != 0 }
        let shown = [rawAmount, debit, credit].first { !$0.isEmpty } ?? ""

        if let (kind, isAdjustment) = type(from: typeText) {
            // The app's own rows store direction in Type, so a negative amount there is a mistake.
            let amount = rawAmount.isEmpty ? signed.map { abs($0) } : decimal(from: rawAmount)
            guard let amount, amount > 0 else { throw RecordCSVError.invalidAmount(row: row, value: shown) }
            return (kind, isAdjustment, amount)
        }
        if let kind = bankKind(from: typeText) {
            guard let signed else { throw RecordCSVError.invalidAmount(row: row, value: shown) }
            return (kind, false, abs(signed))
        }
        guard !hasTypeColumn || isSigned else { throw RecordCSVError.invalidType(row: row, value: rawType) }
        guard let signed else { throw RecordCSVError.invalidAmount(row: row, value: shown) }
        let value = reversesSigns ? -signed : signed
        return (value < 0 ? .expense : .income, false, abs(value))
    }

    /// Payment-type raw values are camelCase, so match case-insensitively rather than lowercasing
    /// the text and hoping it equals the raw value.
    public static func paymentType(from text: String) -> PaymentType {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return .unspecified }
        return PaymentType.allCases.first { $0.rawValue.lowercased() == name } ?? .unspecified
    }

    /// Accepts the ISO form this app writes, plus the plain date and common spreadsheet and bank
    /// renderings. `dayFirst` decides whether "03/04/2024" is 3 April or March 4.
    public static func date(from text: String, dayFirst: Bool = false) -> Date? {
        parsedDate(from: text, dayFirst: dayFirst)?.date
    }

    private static let monthFirstPatterns = ["MM/dd/yyyy", "MM-dd-yyyy", "MM/dd/yy"]
    private static let dayFirstPatterns = ["dd/MM/yyyy", "dd-MM-yyyy", "dd/MM/yy", "dd-MM-yy"]

    static func parsedDate(from text: String, dayFirst: Bool) -> (date: Date, isDateOnly: Bool)? {
        guard !text.isEmpty else { return nil }
        if let date = formatter.date(from: text) { return (date, false) }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return (date, false) }

        let numeric = dayFirst ? dayFirstPatterns + monthFirstPatterns : monthFirstPatterns + dayFirstPatterns
        let timed = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm"]
            + numeric.filter { $0.hasSuffix("yyyy") }.map { "\($0) HH:mm" }
        let dated = ["yyyy-MM-dd", "yyyy/MM/dd"] + numeric + ["dd.MM.yyyy", "dd.MM.yy",
                     "d MMM yyyy", "d-MMM-yyyy", "d MMM yy", "d-MMM-yy", "MMM d, yyyy", "d MMMM yyyy", "MMMM d, yyyy"]

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        for pattern in timed + dated {
            parser.dateFormat = pattern
            // "yyyy" happily reads "24" as year 24; leave that to the two-digit pattern.
            guard let date = parser.date(from: text),
                  Calendar.current.component(.year, from: date) >= 1900 else { continue }
            return (date, !pattern.contains("HH"))
        }
        return nil
    }

    /// Whether a file's slash or dash dates put the day first, judged from the first date whose
    /// day or month exceeds 12. Dotted dates are always day-first; with no evidence, month-first.
    static func prefersDayFirst(_ dates: [String]) -> Bool {
        for text in dates {
            let datePart = text.split(separator: " ").first.map(String.init) ?? text
            if datePart.contains(".") { return true }
            let parts = datePart.split(whereSeparator: { $0 == "/" || $0 == "-" })
            guard parts.count == 3, parts[0].count <= 2,
                  let first = Int(parts[0]), let second = Int(parts[1]) else { continue }
            if first > 12 { return true }
            if second > 12 { return false }
        }
        return false
    }

    /// Parses an amount written with either decimal separator, ignoring grouping and currency
    /// symbols a spreadsheet may have added. Accounting negatives, "(12.34)" and "12.34-", read
    /// as negative.
    public static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isParenthesized = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        var cleaned = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        let isNegative = isParenthesized || cleaned.hasPrefix("-") || cleaned.hasSuffix("-")
        cleaned.removeAll { $0 == "-" }
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
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return isNegative ? -value : value
    }
}
