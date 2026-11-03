import SwiftUI
import WalletDomain

/// Money owed to and by other people, netted per person.
public struct DebtsView: View {
    @ObservedObject private var viewModel: DebtsViewModel
    @State private var editing: Debt?
    @State private var deleting: DebtProgress?
    @State private var settling: DebtProgress?
    @Environment(\.mainCurrency) private var mainCurrency

    public init(viewModel: DebtsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            ForEach(viewModel.balances) { balance in
                Section {
                    ForEach(balance.debts) { progress in
                        Button { editing = progress.debt } label: { row(progress) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                if !progress.isSettled {
                                    Button("Settle", systemImage: "checkmark") { settling = progress }
                                        .tint(.green)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { deleting = progress }
                            }
                    }
                } header: {
                    header(balance)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.balances.isEmpty && !viewModel.isLoading {
                WalletEmptyState(title: "No debts tracked", symbol: "person.2",
                                 message: "Track money you lent or borrowed, and settle it when it is paid.",
                                 actionTitle: "Add Debt") { editing = Debt(currencyCode: mainCurrency) }
            }
        }
        .navigationTitle("Debts")
        .toolbar { Button("Add Debt", systemImage: "plus") { editing = Debt(currencyCode: mainCurrency) } }
        .sheet(item: $editing) { DebtEditorView(viewModel: viewModel, debt: $0) }
        .sheet(item: $settling) { DebtSettlementView(viewModel: viewModel, progress: $0) }
        .alert("Delete Debt?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let progress = deleting else { return }
                Task {
                    do { try await viewModel.deleteDebt(id: progress.debt.id) }
                    catch { viewModel.errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("Its payment history is removed too. Any records created when settling are kept.")
        }
        .alert("Unable to Update Debts", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .disabled(viewModel.isSaving)
    }

    /// Nets the person's debts, saying in words which way the balance runs.
    private func header(_ balance: PersonBalance) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(balance.person)
            Spacer(minLength: WalletMetrics.small)
            if balance.isSettled {
                Text("Settled").textCase(nil).foregroundStyle(.secondary)
            } else {
                Text(summary(balance))
                    .textCase(nil)
                    .foregroundStyle(balance.net > 0 ? .green : .red)
            }
        }
    }

    private func summary(_ balance: PersonBalance) -> String {
        let amount = abs(balance.net).walletFormatted(balance.currencyCode)
        return balance.net > 0 ? "Owes you \(amount)" : "You owe \(amount)"
    }

    private func row(_ progress: DebtProgress) -> some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: progress.isSettled ? "checkmark.circle"
                                : progress.debt.direction == .owedToMe ? "arrow.down.left" : "arrow.up.right",
                           color: progress.isSettled ? .gray
                                : progress.isOverdue ? .red
                                : progress.debt.direction == .owedToMe ? .green : .orange)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(progress.debt.direction.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail(progress))
                    .font(.caption)
                    .foregroundStyle(progress.isOverdue ? Color.red : Color.secondary)
                    .lineLimit(1)
                if !progress.isSettled, progress.paid > 0 {
                    ProgressView(value: progress.fraction)
                        .tint(progress.debt.direction == .owedToMe ? .green : .orange)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: WalletMetrics.small)
            VStack(alignment: .trailing, spacing: WalletMetrics.hair) {
                Text(progress.outstanding.walletFormatted(progress.debt.currencyCode))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(progress.isSettled ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if progress.paid > 0, !progress.isSettled {
                    Text("of \(progress.debt.amount.walletFormatted(progress.debt.currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func detail(_ progress: DebtProgress) -> String {
        if progress.isSettled { return "Settled" }
        guard let due = progress.debt.dueDate else {
            return progress.paid > 0 ? "\(progress.paid.walletFormatted(progress.debt.currencyCode)) paid" : "No due date"
        }
        let when = due.formatted(date: .abbreviated, time: .omitted)
        return progress.isOverdue ? "Overdue · \(when)" : "Due \(when)"
    }
}

/// Create or edit a debt.
private struct DebtEditorView: View {
    @ObservedObject var viewModel: DebtsViewModel
    @State var debt: Debt
    @State private var amount = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !viewModel.debts.contains { $0.debt.id == debt.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Debt") {
                    LabeledContent("Person") {
                        TextField("Name", text: $debt.person).multilineTextAlignment(.trailing)
                    }
                    Picker("Direction", selection: $debt.direction) {
                        ForEach(DebtDirection.allCases) { Text($0.title).tag($0) }
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
                    NavigationLink {
                        CurrencyPickerView(selection: $debt.currencyCode, pushed: true)
                    } label: {
                        LabeledContent("Currency", value: debt.currencyCode)
                    }
                }

                Section {
                    Toggle("Has a due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        Toggle("Remind me", isOn: $debt.notificationsEnabled)
                        if debt.notificationsEnabled {
                            Button("Enable System Notifications") {
                                Task { await viewModel.requestNotifications() }
                            }
                        }
                    }
                } header: {
                    Text("Due date")
                } footer: {
                    Text("Reminders only fire while the debt is still outstanding.")
                }

                Section("Note") {
                    TextField("Optional", text: $debt.note, axis: .vertical).lineLimit(1...6)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Debt" : "Edit Debt")
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
                amount = debt.amount == 0 ? "" : AccountAmountInput.text(debt.amount)
                hasDueDate = debt.dueDate != nil
                dueDate = debt.dueDate ?? Date()
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
                var value = debt
                value.amount = try AccountAmountInput.parse(amount)
                value.dueDate = hasDueDate ? dueDate : nil
                if !hasDueDate { value.notificationsEnabled = false }
                try await viewModel.save(value)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

/// Records a payment against a debt, optionally writing a matching ledger record.
private struct DebtSettlementView: View {
    @ObservedObject var viewModel: DebtsViewModel
    let progress: DebtProgress
    @State private var amount = ""
    @State private var createsRecord = true
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// Only accounts in the debt's own currency, so the ledger record cannot misstate the amount.
    private var accounts: [Account] {
        viewModel.records.accounts.filter { $0.currencyCode == progress.debt.currencyCode }
    }

    private var account: Account? { accounts.first { $0.id == accountID } ?? accounts.first }

    private var parsed: Decimal? {
        guard let value = try? AccountAmountInput.parse(amount), value > 0,
              value <= progress.outstanding else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Outstanding",
                                   value: progress.outstanding.walletFormatted(progress.debt.currencyCode))
                    LabeledContent("Amount") {
                        WalletAmountField(amount: amount) {
                            TextField("", text: $amount.groupedAmount())
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                        }
                        .monospacedDigit()
                    }
                    Button("Pay It All") {
                        amount = AccountAmountInput.text(progress.outstanding)
                    }
                } header: {
                    Text(progress.debt.direction == .owedToMe ? "Received from \(progress.debt.person)"
                                                              : "Paid to \(progress.debt.person)")
                } footer: {
                    Text("A payment cannot exceed what is still outstanding.")
                }

                Section {
                    Toggle("Also add a record", isOn: $createsRecord.animation())
                    if createsRecord {
                        if accounts.isEmpty {
                            Label("No account uses \(progress.debt.currencyCode).",
                                  systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        } else {
                            WalletMenuPicker("Account", selection: Binding(get: { account?.id }, set: { accountID = $0 }),
                                             value: account?.name ?? "") {
                                ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                            }
                            WalletMenuPicker("Category", selection: $categoryID,
                                             value: categoryID == nil ? "None" : viewModel.records.categoryName(categoryID)) {
                                Text("None").tag(nil as UUID?)
                                ForEach(viewModel.records.categories) {
                                    Text(viewModel.records.categoryName($0.id)).tag(Optional($0.id))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Ledger")
                } footer: {
                    Text(createsRecord
                         ? "Creates a \(progress.debt.direction.settlementKind.title.lowercased()) in the chosen account so balances and statistics stay right."
                         : "The payment is tracked against the debt only; no balance changes.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settle Debt")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .disabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record Payment") { pay() }
                        .disabled(parsed == nil || viewModel.isSaving
                                  || (createsRecord && account == nil))
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }

    private func pay() {
        guard let value = parsed else { return }
        Task {
            do {
                try await viewModel.pay(progress, amount: value,
                                        account: createsRecord ? account : nil,
                                        categoryID: createsRecord ? categoryID : nil)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
