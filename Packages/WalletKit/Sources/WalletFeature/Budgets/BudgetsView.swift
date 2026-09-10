import SwiftUI
import WalletDomain

struct BudgetsView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: Budget?
    @State private var deleting: Budget?
    @State private var date = Date()

    var body: some View {
        List {
            DatePicker("Budget vs. actual on", selection: $date, displayedComponents: .date)
            ForEach(viewModel.progress(on: date)) { progress in
                BudgetProgressRow(progress: progress)
            }
            Section("Budget definitions") {
                if viewModel.budgets.isEmpty { Text("Create a budget to track spending limits.") }
                ForEach(viewModel.budgets) { budget in
                    Button { editing = budget } label: {
                        LabeledContent(budget.name, value: budget.amount.formatted(.currency(code: budget.currencyCode)))
                    }
                    .contextMenu { Button("Delete", role: .destructive) { deleting = budget } }
                    .swipeActions { Button("Delete", role: .destructive) { deleting = budget } }
                }
            }
            Text("Budgets use expenses from included accounts in the selected currency. Weekly/monthly periods start on the chosen date; only unused positive amounts roll over.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Budgets")
        .toolbar { Button("Add Budget", systemImage: "plus") { editing = Budget() } }
        .sheet(item: $editing) { BudgetEditorView(viewModel: viewModel, budget: $0) }
        .alert("Delete Budget?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let budget = deleting else { return }
                Task { do { try await viewModel.deleteBudget(id: budget.id) } catch { viewModel.errorMessage = error.localizedDescription } }
            }
        } message: { Text("Records are kept. The budget and its notifications are removed.") }
        .disabled(viewModel.isSaving)
    }
}

private struct BudgetEditorView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var budget: Budget
    @State private var amount = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $budget.name)
                TextField("Limit", text: $amount)
                Picker("Currency", selection: $budget.currencyCode) {
                    ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Category", selection: $budget.categoryID) {
                    Text("Overall").tag(nil as UUID?)
                    ForEach(viewModel.records.categories) { Text(viewModel.records.categoryTitle($0.id)).tag(Optional($0.id)) }
                }
                Picker("Period", selection: $budget.period) {
                    ForEach(BudgetPeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                DatePicker("Starts", selection: $budget.startDate, displayedComponents: .date)
                if budget.period == .custom { DatePicker("Ends (exclusive)", selection: $budget.endDate, in: budget.startDate..., displayedComponents: .date) }
                else { Toggle("Roll over unused amounts", isOn: $budget.rollover) }
                Toggle("Notify at 80% and 100%", isOn: $budget.notificationsEnabled)
                if budget.notificationsEnabled { Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                    if let message = viewModel.errorMessage { Text(message).foregroundStyle(.red) } }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Budget")
            .disabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                budget.amount = try AccountAmountInput.parse(amount)
                                budget.startDate = Calendar.current.startOfDay(for: budget.startDate)
                                budget.endDate = Calendar.current.startOfDay(for: budget.endDate)
                                try await viewModel.save(budget)
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }.disabled(viewModel.isSaving)
                }
            }
            .task { amount = budget.amount == 0 ? "" : AccountAmountInput.text(budget.amount) }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }
}
