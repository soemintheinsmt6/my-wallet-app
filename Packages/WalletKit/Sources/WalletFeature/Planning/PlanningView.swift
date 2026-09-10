import SwiftUI

public struct PlanningView: View {
    @ObservedObject var viewModel: PlanningViewModel
    public init(viewModel: PlanningViewModel) { self.viewModel = viewModel }
    public var body: some View {
        NavigationStack {
            List {
                NavigationLink { BudgetsView(viewModel: viewModel) } label: { Label("Budgets", systemImage: "chart.bar.fill") }
                NavigationLink { RecurringView(viewModel: viewModel) } label: { Label("Recurring", systemImage: "repeat") }
                NavigationLink { BillRemindersView(viewModel: viewModel) } label: { Label("Bills", systemImage: "calendar.badge.clock") }
                NavigationLink { ReportsView(records: viewModel.records) } label: { Label("Reports", systemImage: "doc.richtext") }
                if viewModel.isLoading { ProgressView("Refreshing plans…") }
                Section("Budget progress") {
                    ForEach(viewModel.progress()) { BudgetProgressRow(progress: $0) }
                }
            }
            .navigationTitle("Planning")
            .refreshable { await viewModel.refresh(generate: true) }
            .alert("Unable to Update Planning", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }
}
