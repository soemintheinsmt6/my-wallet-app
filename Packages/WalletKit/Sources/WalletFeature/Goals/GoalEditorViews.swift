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
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !viewModel.goals.contains { $0.goal.id == goal.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    LabeledContent("Name") {
                        TextField("New laptop", text: $goal.name).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Target") {
                        WalletAmountField(amount: target) {
                            TextField("", text: $target.groupedAmount())
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                        }
                        .monospacedDigit()
                    }
                    Picker("Currency", selection: $goal.currencyCode) {
                        ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Picker("Account", selection: $goal.accountID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(viewModel.records.accounts.filter { $0.currencyCode == goal.currencyCode }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                } header: {
                    Text("Where the money sits")
                } footer: {
                    Text("Optional, and for reference only. Progress comes from contributions you record, not from the account balance, so spending from that account does not silently undo it.")
                }

                Section {
                    Toggle("Has a deadline", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("By", selection: $deadline, displayedComponents: .date)
                    }
                } header: {
                    Text("Deadline")
                } footer: {
                    Text("Used to say whether your current saving rate gets there in time.")
                }

                Section("Note") {
                    TextField("Optional", text: $goal.note, axis: .vertical).lineLimit(1...6)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Goal" : "Edit Goal")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .disabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(viewModel.isSaving)
                }
            }
            .task {
                target = goal.targetAmount == 0 ? "" : AccountAmountInput.text(goal.targetAmount)
                hasDeadline = goal.deadline != nil
                deadline = goal.deadline ?? Date()
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
        #endif
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
    @Environment(\.dismiss) private var dismiss

    private var accounts: [Account] {
        viewModel.records.accounts.filter { $0.currencyCode == progress.goal.currencyCode }
    }

    private var parsed: Decimal? {
        guard let value = try? AccountAmountInput.parse(amount), value > 0 else { return nil }
        return isWithdrawal ? -value : value
    }

    /// A transfer needs two distinct accounts; a withdrawal cannot be recorded as one here.
    private var canMoveMoney: Bool { accounts.count >= 2 && !isWithdrawal }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isWithdrawal.animation()) {
                        Text("Contribution").tag(false)
                        Text("Withdrawal").tag(true)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Amount") {
                        WalletAmountField(amount: amount) {
                            TextField("", text: $amount.groupedAmount())
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                        }
                        .monospacedDigit()
                    }
                    if !isWithdrawal, progress.remaining > 0 {
                        Button("Finish the Goal") {
                            amount = AccountAmountInput.text(progress.remaining)
                        }
                    }
                } header: {
                    Text(progress.goal.name)
                } footer: {
                    Text("Saved so far: \(progress.saved.walletFormatted(progress.goal.currencyCode)) of \(progress.goal.targetAmount.walletFormatted(progress.goal.currencyCode)).")
                }

                if canMoveMoney {
                    Section {
                        Toggle("Also move the money", isOn: $movesMoney.animation())
                        if movesMoney {
                            Picker("From", selection: $fromAccountID) {
                                Text("Choose").tag(nil as UUID?)
                                ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Picker("To", selection: $toAccountID) {
                                Text("Choose").tag(nil as UUID?)
                                ForEach(accounts.filter { $0.id != fromAccountID }) {
                                    Text($0.name).tag(Optional($0.id))
                                }
                            }
                            Picker("Category", selection: $categoryID) {
                                Text("None").tag(nil as UUID?)
                                ForEach(viewModel.records.categories) {
                                    Text(viewModel.records.categoryTitle($0.id)).tag(Optional($0.id))
                                }
                            }
                        }
                    } header: {
                        Text("Ledger")
                    } footer: {
                        Text("Records a transfer between two of your accounts. Leave off to track the contribution against the goal only.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isWithdrawal ? "Withdraw" : "Contribute")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .disabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsed == nil || viewModel.isSaving || (movesMoney && !hasValidTransfer))
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }

    private var hasValidTransfer: Bool {
        guard let from = fromAccountID, let to = toAccountID else { return false }
        return from != to
    }

    private func save() {
        guard let value = parsed else { return }
        Task {
            do {
                let from = movesMoney ? accounts.first { $0.id == fromAccountID } : nil
                let to = movesMoney ? accounts.first { $0.id == toAccountID } : nil
                try await viewModel.contribute(to: progress.goal, amount: value,
                                               from: from, to: to,
                                               categoryID: movesMoney ? categoryID : nil)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
