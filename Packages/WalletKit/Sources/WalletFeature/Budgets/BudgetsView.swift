import SwiftUI
import WalletDomain

struct BudgetsView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: Budget?
    @State private var deleting: Budget?
    @State private var date = Date()
    @Environment(\.mainCurrency) private var mainCurrency

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
                                 actionTitle: "Add Budget") { editing = Budget(currencyCode: mainCurrency) }
            }
        }
        .navigationTitle("Budgets")
        .toolbar { Button("Add Budget", systemImage: "plus") { editing = Budget(currencyCode: mainCurrency) } }
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
        let category = budget.categoryID.map { viewModel.records.categoryName($0) } ?? "All categories"
        return "\(budget.period.rawValue.capitalized) · \(category)"
    }
}

private struct BudgetEditorView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var budget: Budget
    @State private var amount = ""
    @State private var errorMessage: String?
    @State private var choosingCurrency = false
    @State private var confirmingDelete = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case limit }

    private var isNew: Bool { !viewModel.budgets.contains { $0.id == budget.id } }

    /// The chosen category's own symbol and color, as the record editor shows it; a grid for Overall.
    private var categoryIcon: (symbol: String, color: Color) {
        guard let category = viewModel.records.category(budget.categoryID) else { return ("square.grid.2x2.fill", .gray) }
        return (category.symbol, category.colorToken.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Laid out like the record, debt and goal editors: the amount first, large, in the
                // red of the spending it limits.
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Limit")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        RecordAmountField(
                            sign: "", color: .red, label: "Limit amount",
                            currency: budget.currencyCode, amount: $amount, focus: $focusedField, field: .limit
                        ) {
                            focusedField = nil
                            choosingCurrency = true
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent {
                        TextField("Groceries", text: $budget.name)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        WalletFormLabel("Name", symbol: "chart.bar.fill", color: .green)
                    }
                    WalletMenuPicker("Category", selection: $budget.categoryID,
                                     value: budget.categoryID == nil ? "Overall" : viewModel.records.categoryName(budget.categoryID),
                                     icon: categoryIcon) {
                        Text("Overall").tag(nil as UUID?)
                        ForEach(viewModel.records.categories) { Text(viewModel.records.categoryName($0.id)).tag(Optional($0.id)) }
                    }
                }

                Section {
                    WalletMenuPicker("Period", selection: $budget.period, value: budget.period.rawValue.capitalized,
                                     icon: ("repeat", .blue)) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    DatePicker(selection: $budget.startDate, displayedComponents: .date) {
                        WalletFormLabel("Starts", symbol: "calendar", color: .red)
                    }
                    if budget.period == .custom {
                        DatePicker(selection: $budget.endDate, in: budget.startDate..., displayedComponents: .date) {
                            WalletFormLabel("Ends (exclusive)", symbol: "flag.checkered", color: .orange)
                        }
                    } else {
                        Toggle(isOn: $budget.rollover) {
                            WalletFormLabel("Roll over unused amounts", symbol: "arrow.uturn.forward", color: .teal)
                        }
                    }
                } header: {
                    Text("Period")
                } footer: {
                    Text(budget.period == .custom
                         ? "A custom budget covers one fixed date range."
                         : "Only unused positive amounts roll over into the next period.")
                }

                Section {
                    Toggle(isOn: $budget.notificationsEnabled) {
                        WalletFormLabel("Notify at 80% and 100%", symbol: "bell.fill", color: .purple)
                    }
                    .refreshesNotificationAuthorization { await viewModel.refreshNotificationAuthorization() }
                    if budget.notificationsEnabled {
                        if !viewModel.notificationsAuthorized {
                            Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                        }
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

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            focusedField = nil
                            confirmingDelete = true
                        } label: {
                            Label {
                                Text("Delete Budget").foregroundStyle(.red)
                            } icon: {
                                WalletFormIcon(symbol: "trash", color: .red)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .alert("Delete Budget?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Records are kept. The budget and its notifications are removed.")
            }
            .navigationTitle(isNew ? "New Budget" : "Edit Budget")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .scrollDismissesKeyboard(.immediately)
            .navigationDestination(isPresented: $choosingCurrency) {
                CurrencyPickerView(selection: $budget.currencyCode, pushed: true)
            }
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

    /// Keeps the editor open with the error shown if the delete fails.
    private func delete() {
        Task {
            do {
                try await viewModel.deleteBudget(id: budget.id)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
