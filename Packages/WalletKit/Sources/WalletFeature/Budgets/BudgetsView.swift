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
    @State private var confirmingDelete = false
    @State private var screen: Screen?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case limit }
    private enum Screen: Hashable { case currency, name, category }

    private var isNew: Bool { !viewModel.budgets.contains { $0.id == budget.id } }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the limit on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    generalSection
                    periodSection
                    notificationsSection
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding(20) }
                    if !isNew {
                        WalletEditorDeleteButton(title: "Delete Budget") {
                            focusedField = nil
                            confirmingDelete = true
                        }
                    }
                }
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
            }
            .scrollDismissesKeyboard(.immediately)
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
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .currency:
                    CurrencyPickerView(selection: $budget.currencyCode, pushed: true)
                case .name:
                    RecordTextEntry(title: "Name", text: $budget.name, caption: "What is this budget for?")
                case .category:
                    RecordCategoryPicker(viewModel: viewModel.records, kind: .expense, selection: $budget.categoryID,
                                         allowsNone: true, noneTitle: "Overall") { self.screen = nil }
                }
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
            .task {
                // Runs again on returning from a pushed screen; only the first appearance loads.
                guard !didLoad else { return }
                didLoad = true
                amount = budget.amount == 0 ? "" : AccountAmountInput.text(budget.amount)
                if isNew {
                    await Task.yield()
                    focusedField = .limit
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }

    /// Red, the color of the spending it limits; the caption says what the number is.
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Limit")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            RecordAmountField(
                sign: "", color: .red, label: "Limit amount",
                currency: budget.currencyCode, amount: $amount, focus: $focusedField, field: .limit
            ) { open(.currency) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// The category row shows the chosen category's own tile, as the record editor does; a gray
    /// grid stands for Overall. The name takes a tile too, the budget's own green chart from the
    /// Budgets list, so the two rows of the section match.
    @ViewBuilder private var generalSection: some View {
        WalletEditorSectionHeader(title: "General") { focusedField = nil }
        RecordFormRow(symbol: "chart.bar.fill", color: .green, filledIcon: true) {
            WalletEditorNavigationButton(title: "Name", value: budget.name.isEmpty ? nil : budget.name) { open(.name) }
        }
        RecordFormRow(symbol: "square.grid.2x2.fill", category: viewModel.records.category(budget.categoryID),
                      categoryTile: true, showsDivider: false) {
            WalletEditorNavigationButton(
                title: "Category",
                value: budget.categoryID == nil ? "Overall" : viewModel.records.categoryName(budget.categoryID)
            ) { open(.category) }
        }
    }

    @ViewBuilder private var periodSection: some View {
        WalletEditorSectionHeader(title: "Period") { focusedField = nil }
        RecordFormRow(symbol: "repeat") {
            WalletMenuPicker("Period", selection: $budget.period, value: budget.period.rawValue.capitalized) {
                ForEach(BudgetPeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
        RecordFormRow(symbol: "calendar") {
            DatePicker("Starts", selection: $budget.startDate, displayedComponents: .date)
        }
        if budget.period == .custom {
            RecordFormRow(symbol: "calendar.badge.checkmark", showsDivider: false) {
                DatePicker("Ends (exclusive)", selection: $budget.endDate, in: budget.startDate...,
                           displayedComponents: .date)
            }
        } else {
            RecordFormRow(symbol: "arrow.uturn.forward", showsDivider: false) {
                Toggle("Roll over unused amounts", isOn: $budget.rollover)
            }
        }
        WalletEditorCaption(budget.period == .custom
                            ? "A custom budget covers one fixed date range."
                            : "Only unused positive amounts roll over into the next period.")
    }

    @ViewBuilder private var notificationsSection: some View {
        let asksPermission = budget.notificationsEnabled && !viewModel.notificationsAuthorized
        WalletEditorSectionHeader(title: "Notifications") { focusedField = nil }
        RecordFormRow(symbol: "bell", showsDivider: asksPermission) {
            Toggle("Notify at 80% and 100%", isOn: $budget.notificationsEnabled)
        }
        .refreshesNotificationAuthorization { await viewModel.refreshNotificationAuthorization() }
        if asksPermission {
            RecordFormRow(symbol: "bell.badge", color: .accentColor, showsDivider: false) {
                Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                Spacer()
            }
        }
        if budget.notificationsEnabled, let message = viewModel.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
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
