import SwiftUI
import WalletDomain

public struct PlanningView: View {
    @ObservedObject var viewModel: PlanningViewModel

    public init(viewModel: PlanningViewModel) { self.viewModel = viewModel }

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
            .refreshable { await viewModel.refresh(generate: true) }
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
