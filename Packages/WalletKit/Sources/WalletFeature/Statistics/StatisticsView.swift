import Charts
import SwiftUI
import WalletDomain

public struct StatisticsView: View {
    @ObservedObject private var viewModel: RecordsViewModel
    private let planning: PlanningViewModel?
    @Environment(\.scenePhase) private var scenePhase
    @State private var period = Period.month
    @State private var anchor = Date()
    @State private var customStart = Calendar.current.startOfDay(for: Date())
    @State private var customEnd = Date()
    @State private var currency = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var tagID: UUID?
    @State private var granularity = StatisticsGranularity.day

    private enum Period: String, CaseIterable { case week, month, year, custom }

    public init(viewModel: RecordsViewModel, planning: PlanningViewModel? = nil) { self.viewModel = viewModel; self.planning = planning }

    private var accounts: [Account] { viewModel.accounts.filter { !$0.settings.excludeFromStats } }
    private var currencies: [String] { Array(Set(accounts.map(\.currencyCode))).sorted() }
    private var selectedCurrency: String { currencies.contains(currency) ? currency : currencies.first ?? "USD" }
    private var interval: DateInterval {
        let calendar = Calendar.current
        if period == .custom {
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd)))!
            return DateInterval(start: start, end: end)
        }
        let component: Calendar.Component = period == .week ? .weekOfYear : period == .month ? .month : .year
        return calendar.dateInterval(of: component, for: anchor)!
    }
    private var statistics: WalletStatistics {
        WalletStatistics.calculate(records: viewModel.records, accounts: viewModel.accounts,
                                   categories: viewModel.categories,
                                   filter: StatisticsFilter(interval: interval, currencyCode: selectedCurrency,
                                                            accountID: accountID, categoryID: categoryID,
                                                            tagID: tagID, granularity: granularity))
    }

    public var body: some View {
        NavigationStack {
            List {
                filters
                if let planning { BudgetProgressSection(viewModel: planning) }
                if viewModel.isLoading { ProgressView("Loading statistics…") }
                if accounts.isEmpty {
                    Text("Create an account or include an account in statistics to see your activity.")
                } else {
                    let result = statistics
                    Section("Summary · \(selectedCurrency)") {
                        amountRow("Income", result.income)
                        amountRow("Expenses", result.expenses)
                        amountRow("Net", result.net)
                    }
                    breakdown("Expenses by category", values: result.expensesByCategory)
                    breakdown("Income by category", values: result.incomeByCategory)
                    Section("Spending trend") {
                        Picker("Group by", selection: $granularity) {
                            ForEach(StatisticsGranularity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Chart(result.spendingTrend) { point in
                            BarMark(x: .value("Date", point.date), y: .value("Expenses", double(point.amount)))
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(money(point.amount))
                        }
                        .frame(height: 220)
                    }
                    Section("Account balance history") {
                        Chart(result.balanceHistory) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Balance", double(point.amount)))
                                .interpolationMethod(.stepEnd)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(money(point.amount))
                        }
                        .frame(height: 220)
                        Text("Reconstructed from the current base balance and records. Manual balance corrections apply retrospectively. Category and label filters affect activity charts only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Top spending categories") {
                        if result.expensesByCategory.isEmpty { Text("No expenses in this period.").foregroundStyle(.secondary) }
                        ForEach(Array(result.expensesByCategory.prefix(5).enumerated()), id: \.element.id) { index, total in
                            amountRow("\(index + 1). \(viewModel.categoryTitle(total.categoryID))", total.amount)
                        }
                    }
                }
            }
            .navigationTitle("Statistics")
            .refreshable { await viewModel.reload() }
            .task { await viewModel.observe() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await viewModel.reload() } } }
            .onChange(of: selectedCurrency) { _, _ in accountID = nil }
            .alert("Unable to Load Statistics", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("Retry") { Task { await viewModel.reload() } }
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var filters: some View {
        Section("Period and filters") {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            if period == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("Through", selection: $customEnd, in: customStart..., displayedComponents: .date)
            } else { DatePicker("Date in period", selection: $anchor, displayedComponents: .date) }
            Picker("Currency", selection: Binding(get: { selectedCurrency }, set: { currency = $0 })) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
            Picker("Account", selection: $accountID) {
                Text("All included accounts").tag(nil as UUID?)
                ForEach(accounts.filter { $0.currencyCode == selectedCurrency }) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Category", selection: $categoryID) {
                Text("All categories").tag(nil as UUID?)
                ForEach(viewModel.categories) { Text(viewModel.categoryTitle($0.id)).tag(Optional($0.id)) }
            }
            Picker("Label", selection: $tagID) {
                Text("All labels").tag(nil as UUID?)
                ForEach(viewModel.tags) { Text($0.name).tag(Optional($0.id)) }
            }
            Text("Totals are shown separately for each currency. Transfers are excluded from income and expenses. Accounts excluded from stats and unlinked records are omitted.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func breakdown(_ title: String, values: [CategoryTotal]) -> some View {
        Section(title) {
            if values.isEmpty { Text("No activity in this period.").foregroundStyle(.secondary) }
            else {
                Chart(values) { total in
                    SectorMark(angle: .value("Amount", double(total.amount)), innerRadius: .ratio(0.6))
                        .foregroundStyle(viewModel.category(total.categoryID)?.colorToken.color ?? .gray)
                        .accessibilityLabel(viewModel.categoryTitle(total.categoryID))
                        .accessibilityValue(money(total.amount))
                }
                .frame(height: 210)
                ForEach(values) { total in
                    HStack {
                        Circle().fill(viewModel.category(total.categoryID)?.colorToken.color ?? .gray).frame(width: 10, height: 10)
                        amountRow(viewModel.categoryTitle(total.categoryID), total.amount)
                    }
                }
            }
        }
    }

    private func amountRow(_ title: String, _ amount: Decimal) -> some View {
        LabeledContent(title, value: money(amount)).monospacedDigit()
    }
    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: selectedCurrency).precision(.fractionLength(0...8)))
    }
    private func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}
