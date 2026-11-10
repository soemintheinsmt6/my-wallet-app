import SwiftUI
import WalletDomain

/// Create or edit a savings goal.
struct GoalEditorView: View {
    @ObservedObject var viewModel: DebtsViewModel
    @State var goal: SavingsGoal
    @State private var target = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var errorMessage: String?
    @State private var contributing: GoalProgress?
    @State private var confirmingDelete = false
    @State private var screen: Screen?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case target }
    private enum Screen: Hashable { case currency, name, account, note }

    /// The saved goal's live progress; nil while the goal is new.
    private var progress: GoalProgress? { viewModel.goals.first { $0.goal.id == goal.id } }
    private var isNew: Bool { progress == nil }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the target on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    generalSection
                    if let progress { progressSection(progress) }
                    deadlineSection
                    WalletEditorSectionHeader(title: "More Details") { focusedField = nil }
                    RecordFormRow(symbol: "square.and.pencil", showsDivider: false) {
                        WalletEditorNavigationButton(title: "Note", value: goal.note.isEmpty ? nil : goal.note) {
                            open(.note)
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding(20) }
                    if !isNew {
                        WalletEditorDeleteButton(title: "Delete Goal") {
                            focusedField = nil
                            confirmingDelete = true
                        }
                    }
                }
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
                .walletEditorRows()
            }
            .scrollDismissesKeyboard(.immediately)
            .walletEditorPage()
            .alert("Delete Goal?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Its contribution history is removed too. Any transfers created are kept.")
            }
            .navigationTitle(isNew ? "New Goal" : "Edit Goal")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .currency:
                    CurrencyPickerView(selection: $goal.currencyCode, pushed: true)
                case .name:
                    RecordTextEntry(title: "Name", text: $goal.name, caption: "What are you saving for?")
                case .account:
                    RecordAccountSelection(
                        accounts: viewModel.records.accounts.filter { $0.currencyCode == goal.currencyCode },
                        selection: $goal.accountID, title: "Account", noneTitle: "None")
                case .note:
                    RecordTextEntry(title: "Note", text: $goal.note, caption: "Add note", multiline: true)
                }
            }
            .disabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(viewModel.isSaving)
                }
            }
            .task {
                // Runs again on returning from a pushed screen; only the first appearance loads.
                guard !didLoad else { return }
                didLoad = true
                target = goal.targetAmount == 0 ? "" : AccountAmountInput.text(goal.targetAmount)
                hasDeadline = goal.deadline != nil
                deadline = goal.deadline ?? Date()
                if isNew {
                    await Task.yield()
                    focusedField = .target
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .sheet(item: $contributing) { GoalContributionView(viewModel: viewModel, progress: $0) }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
        #endif
    }

    /// Green because saving toward a goal is money kept; the caption says what the number is.
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Target")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            RecordAmountField(
                sign: "", color: .green, label: "Target amount",
                currency: goal.currencyCode, amount: $target, focus: $focusedField, field: .target
            ) { open(.currency) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var generalSection: some View {
        WalletEditorSectionHeader(title: "General") { focusedField = nil }
        // A tile like the account row's below it, so the two rows of the section match.
        RecordFormRow(symbol: "flag.fill", color: .orange, filledIcon: true) {
            WalletEditorNavigationButton(title: "Name", value: goal.name.isEmpty ? nil : goal.name) { open(.name) }
        }
        RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true, showsDivider: false) {
            WalletEditorNavigationButton(title: "Account",
                                         value: viewModel.records.account(goal.accountID)?.name ?? "None") {
                open(.account)
            }
        }
        WalletEditorCaption("Optional, and for reference only. Progress comes from contributions you record, not from the account balance, so spending from that account does not silently undo it.")
    }

    @ViewBuilder private func progressSection(_ progress: GoalProgress) -> some View {
        let currency = progress.goal.currencyCode
        WalletEditorSectionHeader(title: "Progress") { focusedField = nil }
        RecordFormRow(symbol: "banknote") {
            Text("Saved")
            Spacer()
            Text("\(progress.saved.walletFormatted(currency)) of \(progress.goal.targetAmount.walletFormatted(currency))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        RecordFormRow(symbol: "plus.circle.fill", color: .accentColor, showsDivider: false) {
            Button("Add Money") {
                focusedField = nil
                contributing = progress
            }
            .font(.body.weight(.medium))
            Spacer()
        }
    }

    @ViewBuilder private var deadlineSection: some View {
        WalletEditorSectionHeader(title: "Deadline") { focusedField = nil }
        RecordFormRow(symbol: "calendar", showsDivider: hasDeadline) {
            Toggle("Has a deadline", isOn: $hasDeadline.animation())
        }
        if hasDeadline {
            RecordFormRow(symbol: "clock", showsDivider: false) {
                DatePicker("By", selection: $deadline, displayedComponents: .date)
            }
        }
        WalletEditorCaption("Used to say whether your current saving rate gets there in time.")
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
    }

    /// Keeps the editor open with the error shown if the delete fails.
    private func delete() {
        Task {
            do {
                try await viewModel.deleteGoal(id: goal.id)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        Task {
            do {
                var value = goal
                value.targetAmount = try AccountAmountInput.parse(target)
                value.deadline = hasDeadline ? deadline : nil
                try await viewModel.save(value)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

/// Adds to or withdraws from a goal, optionally moving real money as a transfer.
struct GoalContributionView: View {
    @ObservedObject var viewModel: DebtsViewModel
    let progress: GoalProgress
    @State private var amount = ""
    @State private var isWithdrawal = false
    @State private var movesMoney = false
    @State private var fromAccountID: UUID?
    @State private var toAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var errorMessage: String?
    @State private var screen: Screen?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case amount }
    private enum Screen: Hashable { case from, to, category }

    private var accounts: [Account] {
        viewModel.records.accounts.filter { $0.currencyCode == progress.goal.currencyCode }
    }

    private var parsed: Decimal? {
        guard let value = try? AccountAmountInput.parse(amount), value > 0 else { return nil }
        return isWithdrawal ? -value : value
    }

    /// A transfer needs two distinct accounts; a withdrawal cannot be recorded as one here.
    private var canMoveMoney: Bool { accounts.count >= 2 && !isWithdrawal }
    /// The switch only counts while its section shows: switching to a withdrawal hides it, and a
    /// hidden switch must not keep Save waiting for accounts that can no longer be chosen.
    private var transfers: Bool { movesMoney && canMoveMoney }

    private var canSave: Bool { parsed != nil && !viewModel.isSaving && (!transfers || hasValidTransfer) }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the kind and amount on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    goalSection
                    if canMoveMoney { ledgerSection }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
                .walletEditorRows()
            }
            .scrollDismissesKeyboard(.immediately)
            .walletEditorPage()
            .navigationTitle(isWithdrawal ? "Withdraw" : "Contribute")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .from:
                    RecordAccountSelection(accounts: accounts, selection: $fromAccountID, title: "From account")
                case .to:
                    RecordAccountSelection(accounts: accounts.filter { $0.id != fromAccountID },
                                           selection: $toAccountID, title: "To account")
                case .category:
                    RecordCategoryPicker(viewModel: viewModel.records, kind: .transfer,
                                         selection: $categoryID) { self.screen = nil }
                }
            }
            // Moving the money out of the account it was going into would make no transfer.
            .onChange(of: fromAccountID) { _, id in if toAccountID == id { toAccountID = nil } }
            .disabled(viewModel.isSaving)
            // Pinned at the bottom like the record editor's Save.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WalletEditorBottomButton(title: "Save", isBusy: viewModel.isSaving, isEnabled: canSave) { save() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                // Runs again on returning from a pushed screen; only the first appearance focuses.
                guard !didLoad else { return }
                didLoad = true
                await Task.yield()
                focusedField = .amount
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }

    /// Green with a plus for money put toward the goal, red with a minus for money taken out, as
    /// income and expenses are in the record editor. The currency is the goal's, so its chip is not
    /// a button.
    private var amountSection: some View {
        VStack(spacing: 12) {
            Picker("Type", selection: $isWithdrawal.animation()) {
                Text("Contribution").tag(false)
                Text("Withdrawal").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            RecordAmountField(
                sign: isWithdrawal ? "−" : "+", color: isWithdrawal ? .red : .green,
                label: isWithdrawal ? "Withdrawal amount" : "Contribution amount",
                currency: progress.goal.currencyCode, amount: $amount, focus: $focusedField, field: .amount)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Where the goal stands, and a shortcut to the amount that completes it. Both rows lead with
    /// a tile, as the goal editor's name and account rows do.
    @ViewBuilder private var goalSection: some View {
        let currency = progress.goal.currencyCode
        let finishes = !isWithdrawal && progress.remaining > 0
        WalletEditorSectionHeader(title: progress.goal.name) { focusedField = nil }
        RecordFormRow(symbol: "banknote.fill", color: .green, filledIcon: true, showsDivider: finishes) {
            Text("Saved")
            Spacer()
            Text("\(progress.saved.walletFormatted(currency)) of \(progress.goal.targetAmount.walletFormatted(currency))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        if finishes {
            RecordFormRow(symbol: "flag.fill", color: .orange, filledIcon: true, showsDivider: false) {
                Button {
                    focusedField = nil
                    amount = AccountAmountInput.text(progress.remaining)
                } label: {
                    HStack {
                        Text("Finish the Goal").foregroundStyle(.tint)
                        Spacer()
                        Text(progress.remaining.walletFormatted(currency)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The switch and the transfer it records. Every row leads with a tile: the switch's own, the
    /// record editor's wallet for both accounts, and the chosen category's.
    @ViewBuilder private var ledgerSection: some View {
        WalletEditorSectionHeader(title: "Ledger") { focusedField = nil }
        RecordFormRow(symbol: "arrow.left.arrow.right", color: .blue, filledIcon: true, showsDivider: movesMoney) {
            Toggle("Also move the money", isOn: $movesMoney.animation())
        }
        if movesMoney {
            RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true) {
                WalletEditorNavigationButton(title: "From account",
                                             value: viewModel.records.account(fromAccountID)?.name ?? "Choose") {
                    open(.from)
                }
            }
            RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true) {
                WalletEditorNavigationButton(title: "To account",
                                             value: viewModel.records.account(toAccountID)?.name ?? "Choose") {
                    open(.to)
                }
            }
            RecordFormRow(symbol: "questionmark", category: viewModel.records.category(categoryID),
                          categoryTile: true, showsDivider: false) {
                WalletEditorNavigationButton(title: "Category",
                                             value: categoryID == nil ? "None" : viewModel.records.categoryName(categoryID)) {
                    open(.category)
                }
            }
        }
        WalletEditorCaption("Records a transfer between two of your accounts. Leave off to track the contribution "
                            + "against the goal only.")
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
    }

    private var hasValidTransfer: Bool {
        guard let from = fromAccountID, let to = toAccountID else { return false }
        return from != to
    }

    private func save() {
        guard let value = parsed else { return }
        Task {
            do {
                let from = transfers ? accounts.first { $0.id == fromAccountID } : nil
                let to = transfers ? accounts.first { $0.id == toAccountID } : nil
                try await viewModel.contribute(to: progress.goal, amount: value,
                                               from: from, to: to,
                                               categoryID: transfers ? categoryID : nil)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
