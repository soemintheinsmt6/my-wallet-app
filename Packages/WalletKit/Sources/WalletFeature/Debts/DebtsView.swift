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
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case amount }
    private enum Screen: Hashable { case currency, person, note }

    private var isNew: Bool { !viewModel.debts.contains { $0.debt.id == debt.id } }

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
            RecordAmountField(
                sign: "", color: amountColor, label: "\(debt.direction.title) amount",
                currency: debt.currencyCode, amount: $amount, focus: $focusedField, field: .amount
            ) { open(.currency) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
    @State private var screen: Screen?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case amount }
    private enum Screen: Hashable { case account, category }

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

    private var currency: String { progress.debt.currencyCode }
    /// Money in for a debt owed to the user, out for one they owe: the record it can create.
    private var kind: RecordKind { progress.debt.direction.settlementKind }
    private var canSave: Bool { parsed != nil && !viewModel.isSaving && (!createsRecord || account != nil) }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the payment on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    debtSection
                    ledgerSection
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
            .navigationTitle("Settle Debt")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .account:
                    RecordAccountSelection(accounts: accounts,
                                           selection: Binding(get: { account?.id }, set: { accountID = $0 }),
                                           title: "Account")
                case .category:
                    RecordCategoryPicker(viewModel: viewModel.records, kind: kind, selection: $categoryID,
                                         allowsNone: true) { self.screen = nil }
                }
            }
            .disabled(viewModel.isSaving)
            // Pinned at the bottom like the record editor's Save.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WalletEditorBottomButton(title: "Record Payment", isBusy: viewModel.isSaving, isEnabled: canSave) {
                    pay()
                }
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

    /// Green with a plus for money received, red with a minus for money paid, as the income or
    /// expense it can record is in the record editor. The caption says who it is with.
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progress.debt.direction == .owedToMe ? "Received from \(progress.debt.person)"
                                                      : "Paid to \(progress.debt.person)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
            RecordAmountField(kind: kind, currency: currency, amount: $amount, focus: $focusedField, field: .amount)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// What is still owed, and a shortcut to paying all of it. Both rows lead with a tile: the
    /// debt's own from the Debts list, and a checkmark for settling it in full.
    @ViewBuilder private var debtSection: some View {
        WalletEditorSectionHeader(title: "Debt") { focusedField = nil }
        RecordFormRow(symbol: progress.debt.direction == .owedToMe ? "arrow.down.left" : "arrow.up.right",
                      color: progress.debt.direction == .owedToMe ? .green : .orange, filledIcon: true) {
            Text("Outstanding")
            Spacer()
            Text(progress.outstanding.walletFormatted(currency)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        RecordFormRow(symbol: "checkmark", color: .green, filledIcon: true, showsDivider: false) {
            Button {
                focusedField = nil
                amount = AccountAmountInput.text(progress.outstanding)
            } label: {
                HStack {
                    Text("Pay It All").foregroundStyle(.tint)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        WalletEditorCaption("A payment cannot exceed what is still outstanding.")
    }

    /// The switch and the record it creates. Every row leads with a tile: the switch's own, the
    /// record editor's wallet, and the chosen category's.
    @ViewBuilder private var ledgerSection: some View {
        WalletEditorSectionHeader(title: "Ledger") { focusedField = nil }
        RecordFormRow(symbol: "doc.text.fill", color: .blue, filledIcon: true, showsDivider: createsRecord) {
            Toggle("Also add a record", isOn: $createsRecord.animation())
        }
        if createsRecord {
            if accounts.isEmpty {
                RecordFormRow(symbol: "exclamationmark.triangle.fill", color: .orange, filledIcon: true,
                              showsDivider: false) {
                    Text("No account uses \(currency).").foregroundStyle(.orange)
                    Spacer()
                }
                .frame(minHeight: 44)
            } else {
                RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true) {
                    WalletEditorNavigationButton(title: "Account", value: account?.name) { open(.account) }
                }
                RecordFormRow(symbol: "questionmark", category: viewModel.records.category(categoryID),
                              categoryTile: true, showsDivider: false) {
                    WalletEditorNavigationButton(title: "Category",
                                                 value: categoryID == nil ? "None" : viewModel.records.categoryName(categoryID)) {
                        open(.category)
                    }
                }
            }
        }
        WalletEditorCaption(createsRecord
                            ? "Creates \(kind == .income ? "an income" : "an expense") in the chosen account so balances and statistics stay right."
                            : "The payment is tracked against the debt only; no balance changes.")
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
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
