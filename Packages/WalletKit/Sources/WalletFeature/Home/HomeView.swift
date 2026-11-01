import Charts
import SwiftUI
import WalletDomain

/// The landing screen: a dashboard the user arranges, each card linking through to the tab that
/// owns it.
///
/// Everything here is derived from the other view models; the dashboard adds no persistence of its
/// own beyond the arrangement itself.
public struct HomeView: View {
    @ObservedObject private var records: RecordsViewModel
    /// For the account cards' Add tile and each account's own screen.
    @ObservedObject private var accounts: AccountsViewModel
    @ObservedObject private var planning: PlanningViewModel
    /// Optional: with no home currency configured the dashboard keeps per-currency totals.
    @ObservedObject private var currency: CurrencyViewModel
    @ObservedObject private var insights: InsightsViewModel
    @ObservedObject private var dashboard: DashboardViewModel
    @ObservedObject private var debts: DebtsViewModel
    @Binding private var selection: WalletTab
    /// Set by a widget quick-add deep link; presents the editor with that kind preselected.
    @Binding private var pendingAdd: RecordKind?
    @Environment(\.scenePhase) private var scenePhase
    @State private var creating = false
    /// Which currency the balance header shows when more than one is in use.
    @State private var displayedCurrency = ""
    @State private var isArranging = false
    @State private var editingRecord: WalletRecord?
    @State private var creatingAccount = false
    @State private var openAccountID: UUID?

    private let recentLimit = 5
    private let previewLimit = 3

    public init(records: RecordsViewModel, accounts: AccountsViewModel, planning: PlanningViewModel,
                currency: CurrencyViewModel, insights: InsightsViewModel, dashboard: DashboardViewModel,
                debts: DebtsViewModel, selection: Binding<WalletTab>,
                pendingAdd: Binding<RecordKind?> = .constant(nil)) {
        self.records = records
        self.accounts = accounts
        self.planning = planning
        self.currency = currency
        self.insights = insights
        self.dashboard = dashboard
        self.debts = debts
        _selection = selection
        _pendingAdd = pendingAdd
    }

    // MARK: - Derived values

    private var configuration: DashboardConfiguration { dashboard.configuration }

    /// Every account included in statistics. The dashboard is always the whole wallet; one
    /// account at a time is its own screen, opened from the account cards.
    private var includedAccounts: [Account] {
        records.accounts.filter { !$0.settings.excludeFromStats }
    }

    /// Every account for the cards, excluded ones too: a balance is worth seeing either way.
    /// Ordered as the Accounts screen orders them: by type, then by name.
    private var cardAccounts: [Account] {
        AccountType.allCases.flatMap { type in
            records.accounts.filter { $0.type == type }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private var currencies: [String] { Array(Set(includedAccounts.map(\.currencyCode))).sorted() }

    /// The currency holding the most accounts, so a single-currency wallet never sees a picker.
    private var selectedCurrency: String {
        if currencies.contains(displayedCurrency) { return displayedCurrency }
        let counts = Dictionary(grouping: includedAccounts, by: \.currencyCode).mapValues(\.count)
        return counts.max { left, right in
            left.value == right.value ? left.key > right.key : left.value < right.value
        }?.key ?? currencies.first ?? "USD"
    }

    private var totalBalance: Decimal {
        includedAccounts.filter { $0.currencyCode == selectedCurrency }
            .reduce(0) { $0 + $1.settings.currentBalance }
    }

    /// Always the current month.
    private var interval: DateInterval { ActivityPeriod.month.interval(containing: Date()) }

    private var statistics: WalletStatistics {
        WalletStatistics.calculate(records: records.records, accounts: records.accounts,
                                   categories: records.categories,
                                   filter: StatisticsFilter(interval: interval, currencyCode: selectedCurrency))
    }

    private var recentRecords: [WalletRecord] {
        Array(records.records.sorted { $0.draft.date > $1.draft.date }.prefix(recentLimit))
    }

    private var upcomingBills: [BillDue] {
        let due = planning.bills.compactMap { bill -> BillDue? in
            guard let date = bill.nextDueDate else { return nil }
            return BillDue(bill: bill, due: date)
        }
        return Array(due.sorted { $0.due < $1.due }.prefix(previewLimit))
    }

    private var budgetProgress: [BudgetProgress] {
        Array(planning.progress().sorted { $0.ratio > $1.ratio }.prefix(previewLimit))
    }

    private var goalProgress: [GoalProgress] {
        Array(debts.goals.filter { !$0.isAchieved }.prefix(previewLimit))
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            List {
                if includedAccounts.isEmpty {
                    if !records.isLoading { setUpSection }
                } else {
                    ForEach(configuration.visible) { card in
                        section(for: card)
                    }
                    InsightsSection(viewModel: insights) { records.categoryName($0) }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem {
                    Button { isArranging = true } label: {
                        Label("Arrange Dashboard", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem {
                    Button { creating = true } label: { Label("Add Record", systemImage: "plus") }
                        .disabled(records.accounts.isEmpty || records.isLoading)
                }
            }
            .sheet(isPresented: $creating) { RecordEditorView(viewModel: records) }
            .sheet(item: $editingRecord) { RecordEditorView(viewModel: records, record: $0) }
            .sheet(item: $pendingAdd) { kind in
                RecordEditorView(viewModel: records, initialKind: kind)
            }
            .sheet(isPresented: $isArranging) {
                DashboardSettingsView(dashboard: dashboard)
            }
            .sheet(isPresented: $creatingAccount) { AccountEditorView(viewModel: accounts) }
            .navigationDestination(item: $openAccountID) { id in
                AccountDetailView(accounts: accounts, records: records, accountID: id)
            }
            .refreshable { await planning.refresh(generate: true) }
            .overlay {
                if records.isLoading && records.accounts.isEmpty {
                    WalletLoadingState(message: "Opening wallet…")
                }
            }
        }
        .task { await records.observe() }
        .task { await currency.refresh() }
        .task { insights.start() }
        .task { await debts.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await records.reload() } }
        }
    }

    @ViewBuilder private func section(for card: DashboardCard) -> some View {
        switch card {
        case .balance: balanceSection
        case .accounts: accountsSection
        case .quickActions: quickActionsSection
        case .summary: summarySection
        case .spendingChart: spendingChartSection
        case .budgets: budgetSection
        case .goals: goalsSection
        case .bills: billsSection
        case .recent: recentSection
        }
    }

    // MARK: - Cards

    private var setUpSection: some View {
        Section {
            WalletEmptyState(title: "Your wallet starts here", symbol: "wallet.bifold",
                             message: "Create an account to start tracking balances, spending and budgets.",
                             actionTitle: "Go to Accounts") { selection = .more }
                .listRowBackground(Color.clear)
        }
    }

    private var balanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                HStack {
                    Text("Total balance")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if currencies.count > 1 { currencyMenu }
                }
                Text(totalBalance.walletFormatted(selectedCurrency))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(totalBalance < 0 ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.default, value: totalBalance)
                Text(accountSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let combined = combinedTotal {
                    ConvertedAmountText(amount: combined, currencyCode: currency.homeCurrency)
                }
            }
            .padding(.vertical, WalletMetrics.small)
            .accessibilityElement(children: .combine)
        }
    }

    /// Every currency added together in the home currency, shown only when the user asked for
    /// converted totals, more than one currency is in play, and every one of them can be converted.
    private var combinedTotal: Decimal? {
        guard currency.isConversionAvailable, currencies.count > 1 else { return nil }
        let amounts = includedAccounts.map { (amount: $0.settings.currentBalance, currency: $0.currencyCode) }
        return currency.total(amounts)
    }

    private var currencyMenu: some View {
        Menu {
            Picker("Currency", selection: Binding(get: { selectedCurrency }, set: { displayedCurrency = $0 })) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: WalletMetrics.tight) {
                Text(selectedCurrency).font(.footnote.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel("Currency \(selectedCurrency)")
    }

    private var accountSummary: String {
        let matching = includedAccounts.filter { $0.currencyCode == selectedCurrency }.count
        let label = matching == 1 ? "1 account" : "\(matching) accounts"
        return currencies.count > 1 ? "\(label) in \(selectedCurrency)" : label
    }

    /// Every account as a card with its balance, two to a row, and a tile to add another. A card
    /// opens that account's own screen.
    private var accountsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: WalletMetrics.medium),
                                GridItem(.flexible(), spacing: WalletMetrics.medium)],
                      spacing: WalletMetrics.medium) {
                ForEach(cardAccounts) { account in
                    Button { openAccountID = account.id } label: { AccountCard(account: account) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the account")
                }
                Button { creatingAccount = true } label: {
                    VStack(spacing: WalletMetrics.small) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: WalletMetrics.Tile.largeSize, height: WalletMetrics.Tile.largeSize)
                            .background(Color.accentColor, in: Circle())
                        Text("Add account")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: AccountCard.height)
                    .background(.background.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: WalletMetrics.large, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // Edge to edge within the section, so the cards line up with the Balance card above.
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: WalletMetrics.small, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            WalletSectionHeader(title: "Accounts", actionTitle: nil) {}
        }
    }

    private var quickActionsSection: some View {
        Section {
            HStack(spacing: WalletMetrics.medium) {
                ForEach(RecordKind.allCases) { kind in
                    Button { pendingAdd = kind } label: {
                        VStack(spacing: WalletMetrics.small) {
                            WalletIconTile(symbol: kind.symbol, color: kind.tint, large: true)
                            Text(kind.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, WalletMetrics.medium)
                        .background(.background, in: RoundedRectangle(cornerRadius: WalletMetrics.medium,
                                                                      style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(records.accounts.isEmpty)
                    .accessibilityLabel("Add \(kind.title.lowercased())")
                }
            }
            // Same edges as the Balance card and the account cards.
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: WalletMetrics.small, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var summarySection: some View {
        let result = statistics
        return Section {
            WalletSummaryCard(income: result.income, expenses: result.expenses, currencyCode: selectedCurrency)
        } header: {
            WalletSectionHeader(title: "This Month", actionTitle: "Details") {
                selection = .statistics
            }
        }
    }

    @ViewBuilder private var spendingChartSection: some View {
        let trend = statistics.spendingTrend
        Section {
            if trend.allSatisfy({ $0.amount == 0 }) {
                Text("No spending in this period.").foregroundStyle(.secondary)
            } else {
                Chart(trend) { point in
                    BarMark(x: .value("Date", point.date, unit: .day),
                            y: .value("Spent", point.amount.doubleValue))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(WalletMetrics.tight)
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(point.amount.walletFormatted(selectedCurrency))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: WalletMetrics.Chart.compactHeight)
                .padding(.vertical, WalletMetrics.small)
            }
        } header: {
            WalletSectionHeader(title: "Spending", actionTitle: "Details") { selection = .statistics }
        }
    }

    @ViewBuilder private var budgetSection: some View {
        if !budgetProgress.isEmpty {
            Section {
                ForEach(budgetProgress) { BudgetProgressRow(progress: $0) }
            } header: {
                WalletSectionHeader(title: "Budget progress", actionTitle: "All budgets") { selection = .planning }
            }
        }
    }

    @ViewBuilder private var goalsSection: some View {
        if !goalProgress.isEmpty {
            Section {
                ForEach(goalProgress) { progress in
                    HStack(spacing: WalletMetrics.medium) {
                        GoalRing(fraction: progress.fraction, isAchieved: progress.isAchieved)
                            .frame(width: 60)
                        VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                            Text(progress.goal.name).font(.body.weight(.medium)).lineLimit(1)
                            Text("\(progress.saved.walletFormatted(progress.goal.currencyCode)) of \(progress.goal.targetAmount.walletFormatted(progress.goal.currencyCode))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: WalletMetrics.small)
                        Text(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, WalletMetrics.tight)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                WalletSectionHeader(title: "Savings goals", actionTitle: "All goals") { selection = .planning }
            }
        }
    }

    @ViewBuilder private var billsSection: some View {
        if !upcomingBills.isEmpty {
            Section {
                ForEach(upcomingBills) { entry in
                    BillSummaryRow(bill: entry.bill, due: entry.due)
                }
            } header: {
                WalletSectionHeader(title: "Upcoming bills", actionTitle: "All bills") { selection = .planning }
            }
        }
    }

    @ViewBuilder private var recentSection: some View {
        Section {
            if recentRecords.isEmpty {
                Text("No records yet. Add your first expense or income.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentRecords) { record in
                    Button { editingRecord = record } label: {
                        RecordRow(viewModel: records, record: record, showsDate: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            WalletSectionHeader(title: "Recent activity", actionTitle: recentRecords.isEmpty ? nil : "See all") {
                selection = .records
            }
        }
    }
}

/// An account on the dashboard: its icon, name and balance on a card.
struct AccountCard: View {
    let account: Account

    /// Shared with the Add tile so a row of the grid lines up.
    static let height: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            WalletIconTile(symbol: account.symbol, color: account.settings.color.tint)
            Spacer(minLength: 0)
            Text(account.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(account.settings.currentBalance.walletFormatted(account.currencyCode))
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(account.settings.currentBalance < 0 ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(WalletMetrics.medium)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: WalletMetrics.large, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A bill paired with its resolved next due date, so the dashboard can sort and identify it.
struct BillDue: Identifiable {
    let bill: BillReminder
    let due: Date
    var id: UUID { bill.id }
}

/// A read-only bill line used by the dashboard; the Bills screen owns the editable version.
struct BillSummaryRow: View {
    let bill: BillReminder
    let due: Date

    private var isOverdue: Bool { due < Date() }

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: isOverdue ? "exclamationmark.circle" : "calendar",
                           color: isOverdue ? .red : .orange)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(bill.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(isOverdue ? "Overdue" : "Due") \(due.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
            }
            Spacer(minLength: WalletMetrics.small)
            WalletAmountText(amount: bill.amount, currencyCode: bill.currencyCode, tint: .primary)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .accessibilityElement(children: .combine)
    }
}
