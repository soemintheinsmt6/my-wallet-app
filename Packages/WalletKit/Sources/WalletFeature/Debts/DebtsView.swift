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
                // Visible, as bills carry Pay, so settling never depends on discovering the swipe.
                if !progress.isSettled {
                    Button("Settle") { settling = progress }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(progress.isOverdue ? .red : progress.debt.direction == .owedToMe ? .green : .orange)
                        .accessibilityLabel("Settle \(progress.debt.direction.title.lowercased()), \(progress.debt.person)")
                }
            }
            // Tapping opens the debt's editor.
            WalletDisclosure()
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
    @State private var confirmingDelete = false
    @State private var screen: Screen?
    @State private var didLoad = false
    @State private var movesMoney = false
    @State private var moneyAccountID: UUID?
    @State private var editingRecord: WalletRecord?
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case amount }
    private enum Screen: Hashable { case currency, person, note, moneyAccount }

    private var isNew: Bool { !viewModel.debts.contains { $0.debt.id == debt.id } }

    /// Accounts in the debt's currency, so the recorded money matches the debt.
    private var moneyAccounts: [Account] {
        viewModel.records.accounts.filter { $0.currencyCode == debt.currencyCode }
    }

    private var moneyAccount: Account? { moneyAccounts.first { $0.id == moneyAccountID } ?? moneyAccounts.first }

    /// The account the opening adjustment was recorded on, once it exists.
    private var openingAccount: Account? {
        guard let id = debt.openingRecordID,
              let record = viewModel.records.records.first(where: { $0.id == id }) else { return nil }
        return viewModel.records.account(record.draft.accountID)
    }

    /// Green for money coming to the user, red for money they owe, as income and expenses are.
    private var amountColor: Color { debt.direction == .owedToMe ? .green : .red }

    var body: some View {
        NavigationStack {
            // The record editor's layout: who owes whom and the amount on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    WalletEditorSectionHeader(title: "General") { focusedField = nil }
                    RecordFormRow(symbol: "person", showsDivider: false) {
                        WalletEditorNavigationButton(title: "Person", value: debt.person.isEmpty ? nil : debt.person) {
                            open(.person)
                        }
                    }
                    moneySection
                    recordsSection
                    dueDateSection
                    WalletEditorSectionHeader(title: "More Details") { focusedField = nil }
                    RecordFormRow(symbol: "square.and.pencil", showsDivider: false) {
                        WalletEditorNavigationButton(title: "Note", value: debt.note.isEmpty ? nil : debt.note) {
                            open(.note)
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding(20) }
                    if !isNew {
                        WalletEditorDeleteButton(title: "Delete Debt") {
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
            .sheet(item: $editingRecord) { RecordEditorView(viewModel: viewModel.records, record: $0) }
            .alert("Delete Debt?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("Its payment history is removed too. Any records created when settling are kept.")
            }
            .navigationTitle(isNew ? "New Debt" : "Edit Debt")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .currency:
                    CurrencyPickerView(selection: $debt.currencyCode, pushed: true)
                case .person:
                    RecordTextEntry(title: "Person", text: $debt.person, caption: "Who is it with?",
                                    suggestions: personSuggestions)
                case .note:
                    RecordTextEntry(title: "Note", text: $debt.note, caption: "Add note", multiline: true)
                case .moneyAccount:
                    RecordAccountSelection(accounts: moneyAccounts,
                                           selection: Binding(get: { moneyAccount?.id }, set: { moneyAccountID = $0 }),
                                           title: "Account")
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
                amount = debt.amount == 0 ? "" : AccountAmountInput.text(debt.amount)
                hasDueDate = debt.dueDate != nil
                dueDate = debt.dueDate ?? Date()
                if isNew {
                    await Task.yield()
                    focusedField = .amount
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
        #endif
    }

    private var amountSection: some View {
        VStack(spacing: 12) {
            Picker("Direction", selection: $debt.direction) {
                ForEach(DebtDirection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Once the money is recorded on an account, the currency is that account's: it no
            // longer opens the picker.
            RecordAmountField(
                sign: "", color: amountColor, label: "\(debt.direction.title) amount",
                currency: debt.currencyCode, amount: $amount, focus: $focusedField, field: .amount,
                chooseCurrency: debt.movedMoney ? nil : { open(.currency) })
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Whether the money changed hands when the debt was made. Recorded as a balance adjustment, so
    /// the balance is right while the loan counts as neither spending nor income; settling records
    /// its return the same way. Both rows lead with a tile, as the record editor's account row does.
    /// The records this debt wrote: the money lent or borrowed, then each settlement that added one,
    /// oldest first. Records the person has since deleted are left out.
    private var linkedRecords: [WalletRecord] {
        guard let progress = viewModel.debts.first(where: { $0.debt.id == debt.id }) else { return [] }
        let ids = [progress.debt.openingRecordID].compactMap { $0 } + progress.payments.compactMap(\.recordID)
        return ids.compactMap { id in viewModel.records.records.first { $0.id == id } }
    }

    /// The same rows as the Records list, so the debt's money is seen as it appears there; each
    /// opens its record.
    @ViewBuilder private var recordsSection: some View {
        let records = linkedRecords
        if !records.isEmpty {
            WalletEditorSectionHeader(title: "Records") { focusedField = nil }
            ForEach(records) { record in
                Button {
                    focusedField = nil
                    editingRecord = record
                } label: {
                    RecordRow(viewModel: viewModel.records, record: record, showsDate: true)
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit record")
                if record.id != records.last?.id { Divider().padding(.leading, 68) }
            }
        }
    }

    /// The person as typed, or a stand-in while it is still empty.
    private var personName: String {
        let name = debt.person.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "them" : name
    }

    @ViewBuilder private var moneySection: some View {
        let lending = debt.direction == .owedToMe
        WalletEditorSectionHeader(title: "Money") { focusedField = nil }
        if debt.movedMoney {
            RecordFormRow(symbol: "arrow.left.arrow.right", color: .blue, filledIcon: true, showsDivider: false) {
                Text(lending ? "Lent from" : "Borrowed into")
                Spacer()
                Text(openingAccount?.name ?? "Recorded").foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            WalletEditorCaption("Recorded as a balance adjustment when the debt was made. Changing the amount "
                                + "updates it, and settling records the money's return the same way.")
        } else {
            RecordFormRow(symbol: "arrow.left.arrow.right", color: .blue, filledIcon: true, showsDivider: movesMoney) {
                Toggle(lending ? "Take from my balance now" : "Add to my balance now", isOn: $movesMoney.animation())
            }
            if movesMoney {
                if moneyAccounts.isEmpty {
                    RecordFormRow(symbol: "exclamationmark.triangle.fill", color: .orange, filledIcon: true,
                                  showsDivider: false) {
                        Text("No account uses \(debt.currencyCode).").foregroundStyle(.orange)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                } else {
                    RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true, showsDivider: false) {
                        WalletEditorNavigationButton(title: lending ? "From account" : "Into account",
                                                     value: moneyAccount?.name) { open(.moneyAccount) }
                    }
                }
            }
            WalletEditorCaption(movesMoney
                ? "Records \"" + (lending ? "Lent to" : "Borrowed from") + " \(personName)\" on this account, "
                    + (lending ? "taking the money out" : "adding the money") + " without counting it as "
                    + (lending ? "spending" : "income") + ". Settling records \"Repaid "
                    + (lending ? "by" : "to") + " \(personName)\" the same way."
                : "Leave off if this money is already in your balance, or if no cash changed hands, "
                    + "such as a bill you paid that they owe you part of. Settling then records income or an expense.")
        }
    }

    @ViewBuilder private var dueDateSection: some View {
        WalletEditorSectionHeader(title: "Due Date") { focusedField = nil }
        RecordFormRow(symbol: "calendar", showsDivider: hasDueDate) {
            Toggle("Has a due date", isOn: $hasDueDate.animation())
        }
        if hasDueDate {
            RecordFormRow(symbol: "clock") {
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
            }
            let asksPermission = debt.notificationsEnabled && !viewModel.notificationsAuthorized
            RecordFormRow(symbol: "bell", showsDivider: asksPermission) {
                Toggle("Remind me", isOn: $debt.notificationsEnabled)
            }
            .refreshesNotificationAuthorization { await viewModel.refreshNotificationAuthorization() }
            if asksPermission {
                RecordFormRow(symbol: "bell.badge", color: .accentColor, showsDivider: false) {
                    Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                    Spacer()
                }
            }
            WalletEditorCaption("Reminders only fire while the debt is still outstanding.")
        }
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
    }

    /// People already in the debt list, so the same person is spelled the same way and nets together.
    private func personSuggestions(for text: String) -> [TextEntrySuggestion] {
        var seen = Set<String>()
        let names = viewModel.debts.map(\.debt.person).filter { name in
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return false }
            return text.isEmpty || name.localizedCaseInsensitiveContains(text)
        }
        return names.prefix(8).map { TextEntrySuggestion(text: $0) }
    }

    /// Keeps the editor open with the error shown if the delete fails.
    private func delete() {
        Task {
            do {
                try await viewModel.deleteDebt(id: debt.id)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        Task {
            do {
                var value = debt
                value.amount = try AccountAmountInput.parse(amount)
                value.dueDate = hasDueDate ? dueDate : nil
                if !hasDueDate { value.notificationsEnabled = false }
                let movingThrough = movesMoney && !debt.movedMoney ? moneyAccount : nil
                if movesMoney && !debt.movedMoney && movingThrough == nil {
                    errorMessage = "Add a \(debt.currencyCode) account to record the money, or turn off Money moved now."
                    return
                }
                try await viewModel.save(value, moneyMovedThrough: movingThrough)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
