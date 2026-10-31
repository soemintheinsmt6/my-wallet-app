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
    @State private var filtering = false
    @State private var granularity = StatisticsGranularity.day

    private enum Period: String, CaseIterable, Identifiable {
        case week, month, year, custom
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var component: Calendar.Component? {
            switch self {
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            case .custom: nil
            }
        }
    }

    public init(viewModel: RecordsViewModel, planning: PlanningViewModel? = nil) { self.viewModel = viewModel; self.planning = planning }

    // MARK: - Derived values

    private var accounts: [Account] { viewModel.accounts.filter { !$0.settings.excludeFromStats } }
    private var currencies: [String] { Array(Set(accounts.map(\.currencyCode))).sorted() }
    private var selectedCurrency: String { currencies.contains(currency) ? currency : currencies.first ?? "USD" }

    private var interval: DateInterval {
        let calendar = Calendar.current
        guard let component = period.component else {
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd)))!
            return DateInterval(start: start, end: end)
        }
        return calendar.dateInterval(of: component, for: anchor)!
    }

    private var statistics: WalletStatistics {
        WalletStatistics.calculate(records: viewModel.records, accounts: viewModel.accounts,
                                   categories: viewModel.categories,
                                   filter: StatisticsFilter(interval: interval, currencyCode: selectedCurrency,
                                                            accountID: accountID, categoryID: categoryID,
                                                            tagID: tagID, granularity: granularity))
    }

    private var periodTitle: String {
        switch period {
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
        case .month: return interval.start.formatted(.dateTime.month(.wide).year())
        case .year: return interval.start.formatted(.dateTime.year())
        case .custom:
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private var activeFilters: [String] {
        var names: [String] = []
        if let account = viewModel.account(accountID) { names.append(account.name) }
        if let categoryID { names.append(viewModel.categoryName(categoryID)) }
        if let tag = viewModel.tags.first(where: { $0.id == tagID }) { names.append(tag.name) }
        return names
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            List {
                periodSection
                if !activeFilters.isEmpty { filterSummary }
                if accounts.isEmpty {
                    Section {
                        WalletEmptyState(title: "Nothing to chart yet", symbol: "chart.pie",
                                         message: "Create an account, or include an existing account in statistics, to see your activity.")
                            .listRowBackground(Color.clear)
                    }
                } else {
                    let result = statistics
                    summarySection(result)
                    if let planning { BudgetProgressSection(viewModel: planning) }
                    breakdown("Expenses by category", values: result.expensesByCategory, total: result.expenses)
                    breakdown("Income by category", values: result.incomeByCategory, total: result.income)
                    trendSection(result)
                    historySection(result)
                    topCategoriesSection(result)
                }
            }
            .navigationTitle("Statistics")
            .toolbar { ToolbarItem { filterButton } }
            .sheet(isPresented: $filtering) {
                StatisticsFilterView(viewModel: viewModel, accounts: accounts, selection: filterSelection)
            }
            .refreshable { await viewModel.reload() }
            .overlay {
                if viewModel.isLoading && viewModel.records.isEmpty {
                    WalletLoadingState(message: "Loading statistics…")
                }
            }
            .task { await viewModel.observe() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await viewModel.reload() } } }
            .onChange(of: selectedCurrency) { _, code in
                // The filter sheet may apply a new currency and one of its accounts together.
                if viewModel.account(accountID)?.currencyCode != code { accountID = nil }
            }
            .alert("Unable to Load Statistics", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("Retry") { Task { await viewModel.reload() } }
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    // MARK: - Period

    private var periodSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                      bottom: WalletMetrics.small, trailing: WalletMetrics.large))

            if period == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("Through", selection: $customEnd, in: customStart..., displayedComponents: .date)
            } else {
                periodStepper
            }
        }
    }

    /// Stepping whole periods is how people actually read statistics; a raw date picker made the
    /// user pick an arbitrary day inside the period they wanted.
    private var periodStepper: some View {
        HStack {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: WalletMetrics.touchTarget, height: WalletMetrics.touchTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous \(period.title.lowercased())")

            Spacer()
            Text(periodTitle)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.identity)
            Spacer()

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: WalletMetrics.touchTarget, height: WalletMetrics.touchTarget)
            }
            .buttonStyle(.borderless)
            .disabled(isAtCurrentPeriod)
            .accessibilityLabel("Next \(period.title.lowercased())")
        }
        .accessibilityElement(children: .contain)
    }

    private var isAtCurrentPeriod: Bool { interval.contains(Date()) || interval.start > Date() }

    private func shift(by amount: Int) {
        guard let component = period.component,
              let moved = Calendar.current.date(byAdding: component, value: amount, to: anchor) else { return }
        anchor = moved
    }

    // MARK: - Filters

    private var filterButton: some View {
        Button { filtering = true } label: {
            Label("Filters", systemImage: activeFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityValue(activeFilters.isEmpty ? "No filters" : activeFilters.joined(separator: ", "))
    }

    /// The current filters, with the currency resolved, as the sheet edits and applies them.
    private var filterSelection: Binding<StatisticsFilterSelection> {
        Binding {
            StatisticsFilterSelection(currency: selectedCurrency, accountID: accountID,
                                      categoryID: categoryID, tagID: tagID)
        } set: { value in
            currency = value.currency
            accountID = value.accountID
            categoryID = value.categoryID
            tagID = value.tagID
        }
    }

    private var filterSummary: some View {
        Section {
            HStack {
                Label(activeFilters.joined(separator: " · "), systemImage: "line.3.horizontal.decrease")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Clear") { clearFilters() }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private func clearFilters() {
        accountID = nil
        categoryID = nil
        tagID = nil
    }

    // MARK: - Summary

    private func summarySection(_ result: WalletStatistics) -> some View {
        Section {
            WalletSummaryCard(income: result.income, expenses: result.expenses, currencyCode: selectedCurrency)
        } header: {
            Text("Summary · \(selectedCurrency)")
        } footer: {
            Text("Totals stay separate per currency. Transfers are excluded from income and expenses. Accounts excluded from stats and unlinked records are omitted.")
        }
    }

    // MARK: - Charts

    private func breakdown(_ title: String, values: [CategoryTotal], total: Decimal) -> some View {
        Section(title) {
            if values.isEmpty {
                Text("No activity in this period.").foregroundStyle(.secondary)
            } else {
                Chart(values) { entry in
                    SectorMark(angle: .value("Amount", entry.amount.doubleValue),
                               innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(color(for: entry))
                        .accessibilityLabel(viewModel.categoryName(entry.categoryID))
                        .accessibilityValue(money(entry.amount))
                }
                .chartLegend(.hidden)
                .frame(height: WalletMetrics.Chart.donutHeight)
                .overlay {
                    let short = total.walletShort(selectedCurrency)
                    VStack(spacing: WalletMetrics.hair) {
                        Text("Total").font(.caption2).foregroundStyle(.secondary)
                        Text(short.value)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(short.unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    // Kept inside the hole: the inner radius ratio of the donut, less a margin.
                    .frame(maxWidth: WalletMetrics.Chart.donutHeight * 0.62 - WalletMetrics.large)
                    .accessibilityHidden(true)
                }
                .padding(.vertical, WalletMetrics.small)

                ForEach(values) { entry in
                    categoryLine(entry, total: total)
                }
            }
        }
    }

    private func categoryLine(_ entry: CategoryTotal, total: Decimal) -> some View {
        let share = total > 0 ? (entry.amount / total).doubleValue : 0
        return HStack(spacing: WalletMetrics.medium) {
            Circle()
                .fill(color(for: entry))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(viewModel.categoryName(entry.categoryID))
                .lineLimit(1)
            Spacer(minLength: WalletMetrics.small)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(money(entry.amount))
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func trendSection(_ result: WalletStatistics) -> some View {
        Section {
            Picker("Group by", selection: $granularity) {
                ForEach(StatisticsGranularity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                      bottom: WalletMetrics.small, trailing: WalletMetrics.large))

            if result.spendingTrend.allSatisfy({ $0.amount == 0 }) {
                Text("No expenses in this period.").foregroundStyle(.secondary)
            } else {
                Chart(result.spendingTrend) { point in
                    BarMark(x: .value("Date", point.date, unit: granularity.component),
                            y: .value("Expenses", point.amount.doubleValue))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(WalletMetrics.tight)
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(money(point.amount))
                }
                .chartYAxis { compactYAxis }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: WalletMetrics.Chart.height)
                .padding(.vertical, WalletMetrics.small)
            }
        } header: {
            Text("Spending trend")
        }
    }

    private func historySection(_ result: WalletStatistics) -> some View {
        Section {
            Chart(result.balanceHistory) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Balance", point.amount.doubleValue))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                LineMark(x: .value("Date", point.date), y: .value("Balance", point.amount.doubleValue))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(money(point.amount))
            }
            .chartYAxis { compactYAxis }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: WalletMetrics.Chart.height)
            .padding(.vertical, WalletMetrics.small)
        } header: {
            Text("Account balance history")
        } footer: {
            Text("Reconstructed from the current base balance and records. Manual balance corrections apply retrospectively. Category and label filters affect activity charts only.")
        }
    }

    private func topCategoriesSection(_ result: WalletStatistics) -> some View {
        Section("Top spending categories") {
            if result.expensesByCategory.isEmpty {
                Text("No expenses in this period.").foregroundStyle(.secondary)
            } else {
                let top = Array(result.expensesByCategory.prefix(5))
                let peak = top.first?.amount ?? 0
                ForEach(Array(top.enumerated()), id: \.element.id) { index, entry in
                    VStack(alignment: .leading, spacing: WalletMetrics.small) {
                        HStack(spacing: WalletMetrics.small) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .trailing)
                            Text(viewModel.categoryName(entry.categoryID))
                                .lineLimit(1)
                            Spacer(minLength: WalletMetrics.small)
                            Text(money(entry.amount)).monospacedDigit().lineLimit(1)
                        }
                        ProgressView(value: peak > 0 ? (entry.amount / peak).doubleValue : 0)
                            .tint(color(for: entry))
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, WalletMetrics.tight)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var compactYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine()
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(amount.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                }
            }
        }
    }

    // MARK: - Formatting

    private func color(for entry: CategoryTotal) -> Color {
        viewModel.category(entry.categoryID)?.colorToken.color ?? .gray
    }

    private func money(_ value: Decimal) -> String { value.walletFormatted(selectedCurrency) }
}
