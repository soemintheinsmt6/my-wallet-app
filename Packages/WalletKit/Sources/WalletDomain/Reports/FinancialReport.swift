import Foundation

public struct StatementEntry: Identifiable, Sendable {
    public let record: WalletRecord
    public let change: Decimal
    public let balance: Decimal
    public var id: UUID { record.id }
}

public struct AccountStatement: Sendable {
    public let account: Account
    public let openingBalance: Decimal
    public let closingBalance: Decimal
    public let entries: [StatementEntry]

    public static func calculate(account: Account, records: [WalletRecord], interval: DateInterval) -> AccountStatement {
        func change(_ record: WalletRecord) -> Decimal {
            var result: Decimal = 0
            if record.draft.accountID == account.id {
                result += record.draft.kind == .income ? record.draft.amount : -record.draft.amount
            }
            if record.draft.kind == .transfer && record.draft.destinationAccountID == account.id {
                result += record.draft.receivedAmount ?? record.draft.amount
            }
            return result
        }
        let matching = records.filter { $0.draft.accountID == account.id || $0.draft.destinationAccountID == account.id }.sorted {
            $0.draft.date == $1.draft.date ? $0.id.uuidString < $1.id.uuidString : $0.draft.date < $1.draft.date
        }
        let base = account.settings.currentBalance - matching.reduce(Decimal.zero) { $0 + change($1) }
        let opening = base + matching.filter { $0.draft.date < interval.start }.reduce(Decimal.zero) { $0 + change($1) }
        var balance = opening
        let entries = matching.filter { $0.draft.date >= interval.start && $0.draft.date < interval.end }.map { record in
            let delta = change(record)
            balance += delta
            return StatementEntry(record: record, change: delta, balance: balance)
        }
        return AccountStatement(account: account, openingBalance: opening, closingBalance: balance, entries: entries)
    }
}

public struct FinancialReport: Sendable {
    public let title: String
    public let subtitle: String
    public let sections: [Section]
    public struct Section: Sendable {
        public let title: String
        public let lines: [String]
        public init(title: String, lines: [String]) { self.title = title; self.lines = lines }
    }
    public init(title: String, subtitle: String, sections: [Section]) {
        self.title = title; self.subtitle = subtitle; self.sections = sections
    }
}
