import SwiftUI
import WalletDomain

public struct PlanningView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @ObservedObject private var debts: DebtsViewModel
    @ObservedObject private var splits: SplitsViewModel

    public init(viewModel: PlanningViewModel, debts: DebtsViewModel, splits: SplitsViewModel) {
        self.viewModel = viewModel
        self.debts = debts
        self.splits = splits
    }

    private var progress: [BudgetProgress] { viewModel.progress().sorted { $0.ratio > $1.ratio } }

    private var overdueCount: Int {
        viewModel.bills.compactMap(\.nextDueDate).filter { $0 < Date() }.count
    }

    private var activeSeriesCount: Int { viewModel.series.count }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { BudgetsView(viewModel: viewModel) } label: {
                        PlanningRow(title: "Budgets", detail: budgetDetail,
                                    symbol: "chart.bar.fill", color: .green)
                    }
                    NavigationLink { RecurringView(viewModel: viewModel) } label: {
                        PlanningRow(title: "Recurring", detail: activeSeriesCount == 1 ? "1 series" : "\(activeSeriesCount) series",
                                    symbol: "repeat", color: .indigo)
                    }
                    NavigationLink { BillRemindersView(viewModel: viewModel) } label: {
                        PlanningRow(title: "Bills", detail: billDetail,
                                    symbol: "calendar.badge.clock", color: .orange,
                                    highlighted: overdueCount > 0)
                    }
                    NavigationLink { ReportsView(records: viewModel.records) } label: {
                        PlanningRow(title: "Reports", detail: "Summaries and PDF export",
                                    symbol: "doc.richtext", color: .blue)
                    }
                }

                Section {
                    NavigationLink { DebtsView(viewModel: debts) } label: {
                        PlanningRow(title: "Debts", detail: debtDetail,
                                    symbol: "person.2", color: .teal,
                                    highlighted: debts.debts.contains { $0.isOverdue })
                    }
                    NavigationLink { GoalsView(viewModel: debts) } label: {
                        PlanningRow(title: "Goals", detail: goalDetail, symbol: "target", color: .pink)
                    }
                    NavigationLink { SplitsView(viewModel: splits) } label: {
                        PlanningRow(title: "Shared", detail: splitDetail,
                                    symbol: "person.2.circle", color: .purple)
                    }
                }

                if !progress.isEmpty {
                    Section("Budget progress") {
                        ForEach(progress) { BudgetProgressRow(progress: $0) }
                    }
                }
            }
            .navigationTitle("Planning")
            .overlay {
                if viewModel.isLoading && viewModel.budgets.isEmpty && viewModel.bills.isEmpty {
                    WalletLoadingState(message: "Refreshing plans…")
                }
            }
            .refreshable { await viewModel.refresh(generate: true); await debts.refresh() }
            .task { await debts.refresh() }
            .task { await splits.refresh() }
            .alert("Unable to Update Planning", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var budgetDetail: String {
        let count = viewModel.budgets.count
        guard count > 0 else { return "Set spending limits" }
        let over = progress.filter { $0.ratio >= 1 }.count
        if over > 0 { return over == 1 ? "1 over budget" : "\(over) over budget" }
        return count == 1 ? "1 budget" : "\(count) budgets"
    }

    private var debtDetail: String {
        let outstanding = debts.debts.filter { !$0.isSettled }
        guard !outstanding.isEmpty else { return "Track money lent and borrowed" }
        let overdue = outstanding.filter(\.isOverdue).count
        if overdue > 0 { return overdue == 1 ? "1 overdue" : "\(overdue) overdue" }
        return outstanding.count == 1 ? "1 outstanding" : "\(outstanding.count) outstanding"
    }

    private var splitDetail: String {
        guard !splits.splits.isEmpty else { return "Split bills with people" }
        let owing = splits.settlements.count
        return owing == 0 ? "All settled" : owing == 1 ? "1 payment to settle" : "\(owing) payments to settle"
    }

    private var goalDetail: String {
        guard !debts.goals.isEmpty else { return "Save toward something" }
        let done = debts.goals.filter(\.isAchieved).count
        return done > 0 ? "\(done) of \(debts.goals.count) reached" : "\(debts.goals.count) in progress"
    }

    private var billDetail: String {
        if overdueCount > 0 { return overdueCount == 1 ? "1 overdue" : "\(overdueCount) overdue" }
        let upcoming = viewModel.bills.compactMap(\.nextDueDate).count
        return upcoming == 0 ? "Track due dates" : upcoming == 1 ? "1 upcoming" : "\(upcoming) upcoming"
    }
}

private struct PlanningRow: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    var highlighted = false

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(highlighted ? .red : .secondary)
            }
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.hair)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }
}
