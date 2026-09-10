import SwiftUI
import WalletDomain

/// The landing screen: balance, this month's activity, budget progress, upcoming bills and the
/// most recent records, each linking through to the tab that owns it.
///
/// Everything here is derived from `RecordsViewModel` and `PlanningViewModel`; the dashboard adds
/// no persistence of its own.
public struct HomeView: View {
    @ObservedObject private var records: RecordsViewModel
    @ObservedObject private var planning: PlanningViewModel
    /// Optional: with no home currency configured the dashboard keeps per-currency totals.
    @ObservedObject private var currency: CurrencyViewModel
    @Binding private var selection: WalletTab
    /// Set by a widget quick-add deep link; presents the editor with that kind preselected.
    @Binding private var pendingAdd: RecordKind?
    @Environment(\.scenePhase) private var scenePhase
    @State private var creating = false
    /// Which currency the balance header shows when more than one is in use.
    @State private var displayedCurrency = ""

    private let recentLimit = 5
    private let previewLimit = 3

    public init(records: RecordsViewModel, planning: PlanningViewModel, currency: CurrencyViewModel,
                selection: Binding<WalletTab>, pendingAdd: Binding<RecordKind?> = .constant(nil)) {
        self.records = records
        self.planning = planning
        self.currency = currency
        _selection = selection
        _pendingAdd = pendingAdd
    }

    // MARK: - Derived values

    private var includedAccounts: [Account] { records.accounts.filter { !$0.settings.excludeFromStats } }

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

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date()) ?? DateInterval(start: Date(), duration: 0)
    }

    private var monthStatistics: WalletStatistics {
        WalletStatistics.calculate(records: records.records, accounts: records.accounts,
                                   categories: records.categories,
                                   filter: StatisticsFilter(interval: monthInterval, currencyCode: selectedCurrency))
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

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            List {
                if includedAccounts.isEmpty {
                    if !records.isLoading { setUpSection }
                } else {
                    balanceSection
                    monthSection
                    budgetSection
                    billsSection
                    recentSection
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: WalletRecord.ID.self) { id in
                if let record = records.records.first(where: { $0.id == id }) {
                    RecordDetailView(viewModel: records, record: record)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { creating = true } label: { Label("Add Record", systemImage: "plus") }
                        .disabled(records.accounts.isEmpty || records.isLoading)
                }
            }
            .sheet(isPresented: $creating) { RecordEditorView(viewModel: records) }
            .sheet(item: $pendingAdd) { kind in
                RecordEditorView(viewModel: records, initialKind: kind)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await records.reload() } }
        }
    }

    // MARK: - Sections

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
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .accessibilityLabel("Currency \(selectedCurrency)")
    }

    private var accountSummary: String {
        let matching = includedAccounts.filter { $0.currencyCode == selectedCurrency }.count
        let label = matching == 1 ? "1 account" : "\(matching) accounts"
        return currencies.count > 1 ? "\(label) in \(selectedCurrency)" : label
    }

    private var monthSection: some View {
        let statistics = monthStatistics
        return Section {
            HStack(spacing: WalletMetrics.medium) {
                WalletStatTile(title: "Income", value: statistics.income.walletFormatted(selectedCurrency),
                               symbol: "arrow.down.left", tint: .green)
                WalletStatTile(title: "Expenses", value: statistics.expenses.walletFormatted(selectedCurrency),
                               symbol: "arrow.up.right", tint: .red)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: WalletMetrics.large, bottom: WalletMetrics.small, trailing: WalletMetrics.large))
            .listRowBackground(Color.clear)
            LabeledContent("Net this month") {
                WalletAmountText.net(statistics.net, currencyCode: selectedCurrency)
            }
        } header: {
            WalletSectionHeader(title: Date().formatted(.dateTime.month(.wide).year()), actionTitle: "Details") {
                selection = .statistics
            }
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
                    NavigationLink(value: record.id) {
                        RecordRow(viewModel: records, record: record, showsDate: true)
                    }
                }
            }
        } header: {
            WalletSectionHeader(title: "Recent activity", actionTitle: recentRecords.isEmpty ? nil : "See all") {
                selection = .records
            }
        }
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
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
            Spacer(minLength: WalletMetrics.small)
            WalletAmountText(amount: bill.amount, currencyCode: bill.currencyCode, tint: .primary)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .accessibilityElement(children: .combine)
    }
}
