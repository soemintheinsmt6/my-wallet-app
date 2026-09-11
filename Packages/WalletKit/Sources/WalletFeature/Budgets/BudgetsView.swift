import SwiftUI
import WalletDomain

struct BudgetsView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: Budget?
    @State private var deleting: Budget?
    @State private var date = Date()

    var body: some View {
        List {
            if !viewModel.budgets.isEmpty {
                Section {
                    DatePicker("Compare on", selection: $date, displayedComponents: .date)
                } footer: {
                    Text("Shows budget against actual spending for the period containing this date.")
                }

                Section("Progress") {
                    ForEach(viewModel.progress(on: date)) { BudgetProgressRow(progress: $0) }
                }
            }

            Section {
                ForEach(viewModel.budgets) { budget in
                    Button { editing = budget } label: {
                        HStack(spacing: WalletMetrics.medium) {
                            WalletIconTile(symbol: "chart.bar.fill", color: .green)
                            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                                Text(budget.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(scope(for: budget))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: WalletMetrics.small)
                            Text(budget.amount.walletFormatted(budget.currencyCode))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            WalletDisclosure()
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .padding(.vertical, WalletMetrics.tight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit budget")
                    .contextMenu { Button("Delete", role: .destructive) { deleting = budget } }
                    .swipeActions { Button("Delete", role: .destructive) { deleting = budget } }
                }
            } header: {
                Text("Budget definitions")
            } footer: {
                Text("Budgets use expenses from included accounts in the selected currency. Weekly and monthly periods start on the chosen date; only unused positive amounts roll over.")
            }
        }
        .overlay {
            if viewModel.budgets.isEmpty {
                WalletEmptyState(title: "No budgets yet", symbol: "chart.bar",
                                 message: "Create a budget to track a spending limit for a category or for everything.",
                                 actionTitle: "Add Budget") { editing = Budget() }
            }
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

    private func scope(for budget: Budget) -> String {
        let category = budget.categoryID.map { viewModel.records.categoryTitle($0) } ?? "All categories"
        return "\(budget.period.rawValue.capitalized) · \(category)"
    }
}

private struct BudgetEditorView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var budget: Budget
    @State private var amount = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !viewModel.budgets.contains { $0.id == budget.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budget") {
                    LabeledContent("Name") {
                        TextField("Groceries", text: $budget.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Limit") {
                        TextField("0", text: $amount.groupedAmount())
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                    }
                    Picker("Currency", selection: $budget.currencyCode) {
                        ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Category", selection: $budget.categoryID) {
                        Text("Overall").tag(nil as UUID?)
                        ForEach(viewModel.records.categories) { Text(viewModel.records.categoryTitle($0.id)).tag(Optional($0.id)) }
                    }
                }

                Section {
                    Picker("Period", selection: $budget.period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    DatePicker("Starts", selection: $budget.startDate, displayedComponents: .date)
                    if budget.period == .custom {
                        DatePicker("Ends (exclusive)", selection: $budget.endDate, in: budget.startDate..., displayedComponents: .date)
                    } else {
                        Toggle("Roll over unused amounts", isOn: $budget.rollover)
                    }
                } header: {
                    Text("Period")
                } footer: {
                    Text(budget.period == .custom
                         ? "A custom budget covers one fixed date range."
                         : "Only unused positive amounts roll over into the next period.")
                }

                Section {
                    Toggle("Notify at 80% and 100%", isOn: $budget.notificationsEnabled)
                    if budget.notificationsEnabled {
                        Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                        if let message = viewModel.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Notifications")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Budget" : "Edit Budget")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
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
