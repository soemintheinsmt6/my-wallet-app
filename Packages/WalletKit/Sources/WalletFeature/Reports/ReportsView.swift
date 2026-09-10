import SwiftUI
import UniformTypeIdentifiers
import WalletDomain

struct ReportsView: View {
    @ObservedObject var records: RecordsViewModel
    @State private var period = "Monthly"
    @State private var date = Date()
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Date()
    @State private var currency = "USD"
    @State private var accountID: UUID?
    @State private var shareURL: URL?
    @State private var exportDescription = ""
    @State private var isExporting = false
    @State private var error: String?
    private var interval: DateInterval {
        if period == "Custom" {
            return DateInterval(start: Calendar.current.startOfDay(for: start),
                                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(start, end)))!)
        }
        return Calendar.current.dateInterval(of: period == "Monthly" ? .month : .year, for: date)!
    }
    private var report: FinancialReport {
        let subtitle = "\(interval.start.formatted(date: .abbreviated, time: .omitted)) - \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))"
        if let account = records.account(accountID) {
            let statement = AccountStatement.calculate(account: account, records: records.records, interval: interval)
            func money(_ value: Decimal) -> String { value.formatted(.currency(code: account.currencyCode).precision(.fractionLength(0...8))) }
            return FinancialReport(title: "\(account.name) Statement", subtitle: subtitle, sections: [
                .init(title: "Balances", lines: ["Opening: \(money(statement.openingBalance))", "Closing: \(money(statement.closingBalance))"]),
                .init(title: "Transactions", lines: statement.entries.isEmpty ? ["No records in this period."] : statement.entries.map {
                    "\($0.record.draft.date.formatted(date: .abbreviated, time: .shortened)) | \($0.record.draft.kind.title) | \(records.categoryTitle($0.record.draft.categoryID))\nChange: \(money($0.change)) | Balance: \(money($0.balance))\n\($0.record.draft.payee) \($0.record.draft.note)"
                }),
                .init(title: "Method", lines: ["Balances are reconstructed from current base balances and records. Manual balance corrections apply retrospectively. Transfers use this account's currency."])
            ])
        }
        let result = WalletStatistics.calculate(records: records.records, accounts: records.accounts, categories: records.categories,
                                               filter: StatisticsFilter(interval: interval, currencyCode: currency))
        func money(_ value: Decimal) -> String { value.formatted(.currency(code: currency).precision(.fractionLength(0...8))) }
        func lines(_ totals: [CategoryTotal]) -> [String] {
            totals.isEmpty ? ["No activity in this period."] : totals.map { "\(records.categoryTitle($0.categoryID)): \(money($0.amount))" }
        }
        return FinancialReport(title: "Financial Summary - \(currency)", subtitle: subtitle, sections: [
            .init(title: "Summary", lines: ["Income: \(money(result.income))", "Expenses: \(money(result.expenses))", "Net: \(money(result.net))"]),
            .init(title: "Top Spending Categories", lines: lines(Array(result.expensesByCategory.prefix(5)))),
            .init(title: "Expense Breakdown", lines: lines(result.expensesByCategory)),
            .init(title: "Income Breakdown", lines: lines(result.incomeByCategory)),
            .init(title: "Method", lines: ["Transfers, unlinked activity and accounts excluded from stats are omitted. Currency totals are kept separate."])
        ])
    }
    var body: some View {
        List {
            Section("Report options") {
                Picker("Period", selection: $period) { ForEach(["Monthly", "Yearly", "Custom"], id: \.self) { Text($0).tag($0) } }
                if period == "Custom" {
                    DatePicker("From", selection: $start, displayedComponents: .date)
                    DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                } else { DatePicker("Date in period", selection: $date, displayedComponents: .date) }
                Picker("Report", selection: $accountID) {
                    Text("Financial summary").tag(nil as UUID?)
                    ForEach(records.accounts) { Text("Statement: \($0.name)").tag(Optional($0.id)) }
                }
                if accountID == nil {
                    Picker("Currency", selection: $currency) {
                        ForEach(Array(Set(records.accounts.map(\.currencyCode) + [currency])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .disabled(isExporting)
            let report = report
            Section(report.title) { Text(report.subtitle).foregroundStyle(.secondary) }
            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in Text(line).monospacedDigit() }
                }
            }
            Section("Export") {
                Button("Prepare PDF", systemImage: "doc.richtext") {
                    shareURL = nil
                    isExporting = true
                    Task {
                        do {
                            let data = try await Task.detached { try ReportPDF.data(for: report) }.value
                            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WalletReports", isDirectory: true)
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            let url = directory.appendingPathComponent("Wallet-Report-\(UUID().uuidString).pdf")
                            try data.write(to: url, options: .atomic)
                            exportDescription = "\(report.title) · \(report.subtitle)"
                            shareURL = url
                        } catch { self.error = error.localizedDescription }
                        isExporting = false
                    }
                }.disabled(isExporting)
                if isExporting { ProgressView("Preparing report…") }
                if let shareURL {
                    Text(exportDescription).font(.caption).foregroundStyle(.secondary)
                    ShareLink("Share PDF", item: shareURL)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Reports")
        .onChange(of: period) { _, _ in shareURL = nil }
        .onChange(of: date) { _, _ in shareURL = nil }
        .onChange(of: start) { _, _ in shareURL = nil }
        .onChange(of: end) { _, _ in shareURL = nil }
        .onChange(of: currency) { _, _ in shareURL = nil }
        .onChange(of: accountID) { _, _ in shareURL = nil }
    }
}
