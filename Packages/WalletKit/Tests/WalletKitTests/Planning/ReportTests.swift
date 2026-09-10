import CoreGraphics
import Foundation
import PDFKit
import Testing
import WalletDomain
@testable import WalletFeature

struct ReportTests {
    @Test func statementsIncludeTransferLegsAndExcludeOutOfPeriodChanges() {
        let account = Account(name: "Euro", type: .cash, currencyCode: "EUR", settings: AccountSettings(currentBalance: 90))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var transfer = RecordDraft()
        transfer.accountID = UUID(); transfer.destinationAccountID = account.id; transfer.kind = .transfer
        transfer.amount = 20; transfer.receivedAmount = 18; transfer.date = start
        var expense = RecordDraft()
        expense.accountID = account.id; expense.amount = 8; expense.date = start.addingTimeInterval(3600)
        var future = expense
        future.amount = 20; future.date = start.addingTimeInterval(86400 * 2)
        let records = [WalletRecord(id: UUID(), draft: transfer, currencyCode: "USD", destinationCurrencyCode: "EUR"),
                       WalletRecord(id: UUID(), draft: expense, currencyCode: "EUR"), WalletRecord(id: UUID(), draft: future, currencyCode: "EUR")]
        let statement = AccountStatement.calculate(account: account, records: records, interval: DateInterval(start: start, duration: 86400))
        #expect(statement.openingBalance == 100)
        #expect(statement.entries.map(\.change) == [18, -8])
        #expect(statement.entries.map(\.balance) == [118, 110])
        #expect(statement.closingBalance == 110)
    }

    @Test func pdfPaginatesLongReportsAndPreservesText() throws {
        let report = FinancialReport(title: "Monthly Financial Summary", subtitle: "January 2024 - USD", sections: [
            .init(title: "Summary", lines: ["Income: $4,000.00", "Expenses: $1,234.56", "Net: $2,765.44"]),
            .init(title: "Category Breakdown", lines: (1...70).map { "Category \($0): Food, household and transport - $12.34" }),
            .init(title: "Long note", lines: [String(repeating: "Long receipt note with cafe and travel details. ", count: 60)]),
            .init(title: "Final Balance", lines: ["Closing balance: $9,876.54"])
        ])
        let data = try ReportPDF.data(for: report)
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount >= 3)
        #expect(pdf.string?.contains("Closing balance: $9,876.54") == true)
        #expect(pdf.string?.contains("Category 70") == true)
        // An opt-in QA path exports the exact renderer output for visual inspection.
        if let path = ProcessInfo.processInfo.environment["WALLET_REPORT_QA_PATH"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}
