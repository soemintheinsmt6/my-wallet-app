import SwiftUI
import UniformTypeIdentifiers
import WalletDomain

struct ReportsView: View {
    @ObservedObject var records: RecordsViewModel
    @State private var period = Period.monthly
    @State private var date = Date()
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Date()
    @State private var currency = "USD"
    @State private var accountID: UUID?
    @State private var shareURL: URL?
    @State private var exportDescription = ""
    @State private var isExporting = false
    @State private var error: String?

    private enum Period: String, CaseIterable, Identifiable {
        case monthly, yearly, custom
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var component: Calendar.Component? {
            switch self {
            case .monthly: .month
            case .yearly: .year
            case .custom: nil
            }
        }
        /// The PDF title uses the original wording, so keep the exported label stable.
        var exportName: String { rawValue.capitalized }
    }

    private var interval: DateInterval {
        guard let component = period.component else {
            return DateInterval(start: Calendar.current.startOfDay(for: start),
                                end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(start, end)))!)
        }
        return Calendar.current.dateInterval(of: component, for: date)!
    }

    private var subtitle: String {
        "\(interval.start.formatted(date: .abbreviated, time: .omitted)) - \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))"
    }

    private var selectedAccount: Account? { records.account(accountID) }

    private var statistics: WalletStatistics {
        WalletStatistics.calculate(records: records.records, accounts: records.accounts, categories: records.categories,
                                   filter: StatisticsFilter(interval: interval, currencyCode: currency))
    }

    private var statement: AccountStatement? {
        selectedAccount.map { AccountStatement.calculate(account: $0, records: records.records, interval: interval) }
    }

    // MARK: - Body

    var body: some View {
        List {
            optionsSection
            if let account = selectedAccount, let statement {
                statementSections(account: account, statement: statement)
            } else {
                summarySections(statistics)
            }
            exportSection
        }
        .navigationTitle("Reports")
        .onChange(of: period) { _, _ in shareURL = nil }
        .onChange(of: date) { _, _ in shareURL = nil }
        .onChange(of: start) { _, _ in shareURL = nil }
        .onChange(of: end) { _, _ in shareURL = nil }
        .onChange(of: currency) { _, _ in shareURL = nil }
        .onChange(of: accountID) { _, _ in shareURL = nil }
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                      bottom: WalletMetrics.small, trailing: WalletMetrics.large))

            if period == .custom {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
            } else {
                DatePicker("Date in period", selection: $date, displayedComponents: .date)
            }

            Picker("Report", selection: $accountID) {
                Text("Financial summary").tag(nil as UUID?)
                ForEach(records.accounts) { Text("Statement: \($0.name)").tag(Optional($0.id)) }
            }
            if accountID == nil {
                Picker("Currency", selection: $currency) {
                    ForEach(Array(Set(records.accounts.map(\.currencyCode) + [currency])).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
        } header: {
            Text("Report options")
        } footer: {
            Text(subtitle)
        }
        .disabled(isExporting)
    }

    // MARK: - Financial summary

    @ViewBuilder private func summarySections(_ result: WalletStatistics) -> some View {
        Section {
            HStack(spacing: WalletMetrics.medium) {
                WalletStatTile(title: "Income", value: money(result.income, currency), symbol: "arrow.down.left", tint: .green)
                WalletStatTile(title: "Expenses", value: money(result.expenses, currency), symbol: "arrow.up.right", tint: .red)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: WalletMetrics.large, bottom: WalletMetrics.small, trailing: WalletMetrics.large))
            .listRowBackground(Color.clear)
            LabeledContent("Net") { WalletAmountText.net(result.net, currencyCode: currency) }
        } header: {
            Text("Summary · \(currency)")
        }

        categorySection("Expense breakdown", totals: result.expensesByCategory)
        categorySection("Income breakdown", totals: result.incomeByCategory)

        Section {
            Text("Transfers, unlinked activity and accounts excluded from stats are omitted. Currency totals are kept separate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func categorySection(_ title: String, totals: [CategoryTotal]) -> some View {
        Section(title) {
            if totals.isEmpty {
                Text("No activity in this period.").foregroundStyle(.secondary)
            } else {
                ForEach(totals) { total in
                    HStack(spacing: WalletMetrics.medium) {
                        Circle()
                            .fill(records.category(total.categoryID)?.colorToken.color ?? .gray)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(records.categoryTitle(total.categoryID)).lineLimit(1)
                        Spacer(minLength: WalletMetrics.small)
                        Text(money(total.amount, currency)).monospacedDigit().lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Account statement

    @ViewBuilder private func statementSections(account: Account, statement: AccountStatement) -> some View {
        Section("Balances · \(account.currencyCode)") {
            LabeledContent("Opening") {
                Text(money(statement.openingBalance, account.currencyCode)).monospacedDigit()
            }
            LabeledContent("Closing") {
                Text(money(statement.closingBalance, account.currencyCode)).monospacedDigit()
            }
        }

        Section("Transactions") {
            if statement.entries.isEmpty {
                Text("No records in this period.").foregroundStyle(.secondary)
            } else {
                ForEach(statement.entries, id: \.record.id) { entry in
                    VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                        HStack(spacing: WalletMetrics.small) {
                            Text(records.categoryTitle(entry.record.draft.categoryID))
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: WalletMetrics.small)
                            WalletAmountText.net(entry.change, currencyCode: account.currencyCode,
                                                 font: .body.weight(.semibold))
                        }
                        HStack {
                            Text(entry.record.draft.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer(minLength: WalletMetrics.small)
                            Text("Balance \(money(entry.balance, account.currencyCode))")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if !entry.record.draft.payee.isEmpty || !entry.record.draft.note.isEmpty {
                            Text([entry.record.draft.payee, entry.record.draft.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, WalletMetrics.hair)
                    .accessibilityElement(children: .combine)
                }
            }
        }

        Section {
            Text("Balances are reconstructed from current base balances and records. Manual balance corrections apply retrospectively. Transfers use this account's currency.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Button {
                prepare()
            } label: {
                Label("Prepare PDF", systemImage: "doc.richtext")
            }
            .disabled(isExporting)

            if isExporting { ProgressView("Preparing report…") }

            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                Text(exportDescription).font(.caption).foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("The PDF mirrors what is shown above. Receipt images are not included.")
        }
    }

    private func prepare() {
        shareURL = nil
        error = nil
        isExporting = true
        let report = report
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
    }

    /// The exported document. The on-screen report renders from the same data directly, so this
    /// stays purely the PDF's line-based representation.
    private var report: FinancialReport {
        if let account = selectedAccount, let statement {
            func value(_ amount: Decimal) -> String { money(amount, account.currencyCode) }
            return FinancialReport(title: "\(account.name) Statement", subtitle: subtitle, sections: [
                .init(title: "Balances", lines: ["Opening: \(value(statement.openingBalance))", "Closing: \(value(statement.closingBalance))"]),
                .init(title: "Transactions", lines: statement.entries.isEmpty ? ["No records in this period."] : statement.entries.map {
                    "\($0.record.draft.date.formatted(date: .abbreviated, time: .shortened)) | \($0.record.draft.kind.title) | \(records.categoryTitle($0.record.draft.categoryID))\nChange: \(value($0.change)) | Balance: \(value($0.balance))\n\($0.record.draft.payee) \($0.record.draft.note)"
                }),
                .init(title: "Method", lines: ["Balances are reconstructed from current base balances and records. Manual balance corrections apply retrospectively. Transfers use this account's currency."])
            ])
        }
        let result = statistics
        func value(_ amount: Decimal) -> String { money(amount, currency) }
        func lines(_ totals: [CategoryTotal]) -> [String] {
            totals.isEmpty ? ["No activity in this period."] : totals.map { "\(records.categoryTitle($0.categoryID)): \(value($0.amount))" }
        }
        return FinancialReport(title: "Financial Summary - \(currency)", subtitle: subtitle, sections: [
            .init(title: "Summary", lines: ["Income: \(value(result.income))", "Expenses: \(value(result.expenses))", "Net: \(value(result.net))"]),
            .init(title: "Top Spending Categories", lines: lines(Array(result.expensesByCategory.prefix(5)))),
            .init(title: "Expense Breakdown", lines: lines(result.expensesByCategory)),
            .init(title: "Income Breakdown", lines: lines(result.incomeByCategory)),
            .init(title: "Method", lines: ["Transfers, unlinked activity and accounts excluded from stats are omitted. Currency totals are kept separate."])
        ])
    }

    private func money(_ value: Decimal, _ code: String) -> String { value.walletFormatted(code) }
}
