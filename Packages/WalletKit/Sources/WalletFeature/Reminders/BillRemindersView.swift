import SwiftUI
import WalletDomain

struct BillRemindersView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: BillReminder?
    @State private var paying: BillReminder?
    @State private var deleting: BillReminder?
    @State private var calendarMode = false
    @State private var selectedDate = Date()
    @Environment(\.defaultCurrency) private var defaultCurrency

    private var visibleBills: [BillReminder] {
        guard calendarMode else { return viewModel.bills }
        return viewModel.bills.filter { bill in
            bill.nextDueDate.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } == true
        }
    }

    /// Unpaid bills first, soonest due at the top; settled bills sink to the bottom.
    private var sortedBills: [BillReminder] {
        visibleBills.sorted { first, second in
            switch (first.nextDueDate, second.nextDueDate) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("View", selection: $calendarMode) {
                    Text("List").tag(false)
                    Text("Calendar").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                          bottom: WalletMetrics.small, trailing: WalletMetrics.large))
                if calendarMode {
                    DatePicker("Select a day", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }

            Section(calendarMode ? selectedDate.formatted(date: .abbreviated, time: .omitted) : "Bills") {
                if sortedBills.isEmpty {
                    Text(calendarMode ? "No bills due on this day." : "Add bills to track due dates and payment reminders.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedBills) { bill in row(bill) }
            }
        }
        .navigationTitle("Bills")
        .toolbar { Button("Add Bill", systemImage: "plus") { editing = BillReminder(currencyCode: defaultCurrency) } }
        .sheet(item: $editing) { BillEditorView(viewModel: viewModel, bill: $0) }
        .sheet(item: $paying) { BillPaymentView(viewModel: viewModel, bill: $0) }
        .alert("Delete Bill Reminder?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let bill = deleting else { return }
                Task { do { try await viewModel.deleteBill(id: bill.id) } catch { viewModel.errorMessage = error.localizedDescription } }
            }
        } message: { Text("Existing payment records are kept.") }
        .disabled(viewModel.isSaving)
    }

    /// Tapping opens the bill; unpaid bills also carry a visible Pay button so settling one never
    /// depends on discovering a swipe.
    private func row(_ bill: BillReminder) -> some View {
        let due = bill.nextDueDate
        let isOverdue = due.map { $0 < Date() } ?? false
        return NavigationLink { BillDetailView(viewModel: viewModel, billID: bill.id) } label: {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: BillStatus.symbol(due: due, isOverdue: isOverdue),
                               color: BillStatus.color(due: due, isOverdue: isOverdue))
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text(bill.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(BillStatus.text(due: due, isOverdue: isOverdue))
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                    Text(bill.amount.walletFormatted(bill.currencyCode))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: WalletMetrics.small)
                if due != nil {
                    Button("Pay") { paying = bill }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(isOverdue ? .red : .green)
                        .accessibilityLabel("Mark \(bill.name) as paid")
                }
            }
            .frame(minHeight: WalletMetrics.touchTarget)
            .padding(.vertical, WalletMetrics.tight)
        }
        .accessibilityHint("Show bill details")
        .swipeActions(edge: .leading) {
            if due != nil {
                Button("Mark Paid", systemImage: "checkmark") { paying = bill }.tint(.green)
            }
        }
        .swipeActions {
            Button("Delete", role: .destructive) { deleting = bill }
        }
        .contextMenu {
            if due != nil { Button("Mark as Paid", systemImage: "checkmark") { paying = bill } }
            Button("Edit", systemImage: "pencil") { editing = bill }
            Button("Delete", role: .destructive) { deleting = bill }
        }
    }

}

/// Account and category rows that push a full list instead of popping up a menu.
private struct BillSelectionRows: View {
    @ObservedObject var records: RecordsViewModel
    let accounts: [Account]
    @Binding var bill: BillReminder
    /// The account is always required; the category only when paying.
    var categoryRequired = true
    @State private var choosingCategory = false

    var body: some View {
        NavigationLink {
            RecordAccountSelection(accounts: accounts, selection: $bill.accountID, title: "Account")
        } label: {
            LabeledContent("Account", value: records.account(bill.accountID)?.name ?? "Choose")
        }
        Button { choosingCategory = true } label: {
            LabeledContent("Category") {
                HStack {
                    Text(bill.categoryID == nil ? (categoryRequired ? "Choose" : "None")
                                                : records.categoryTitle(bill.categoryID))
                    WalletDisclosure()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: $choosingCategory) {
            RecordCategoryPicker(viewModel: records, kind: .expense, selection: $bill.categoryID,
                                 allowsNone: !categoryRequired) { choosingCategory = false }
        }
    }
}

/// Shared wording and colour for a bill's next occurrence.
private enum BillStatus {
    static func symbol(due: Date?, isOverdue: Bool) -> String {
        due == nil ? "checkmark.circle" : isOverdue ? "exclamationmark.circle" : "calendar"
    }

    static func color(due: Date?, isOverdue: Bool) -> Color {
        due == nil ? .green : isOverdue ? .red : .orange
    }

    static func text(due: Date?, isOverdue: Bool) -> String {
        guard let due else { return "Paid · complete" }
        let when = due.formatted(date: .abbreviated, time: .omitted)
        return isOverdue ? "Overdue · \(when)" : "Due \(when)"
    }
}

/// One bill at a glance, with paying, editing and deleting as plain rows rather than gestures.
private struct BillDetailView: View {
    @ObservedObject var viewModel: PlanningViewModel
    let billID: UUID
    @State private var editing: BillReminder?
    @State private var paying: BillReminder?
    @State private var confirmingDelete = false
    @State private var mutationError: String?
    @Environment(\.dismiss) private var dismiss

    private var bill: BillReminder? { viewModel.bills.first { $0.id == billID } }

    var body: some View {
        Group {
            if let bill {
                List {
                    header(bill)
                    details(bill)
                    actions(bill)
                }
            } else {
                WalletEmptyState(title: "Bill unavailable", symbol: "calendar.badge.exclamationmark",
                                 message: "Return to Bills and refresh.")
            }
        }
        .navigationTitle(bill?.name ?? "Bill")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { BillEditorView(viewModel: viewModel, bill: $0) }
        .sheet(item: $paying) { BillPaymentView(viewModel: viewModel, bill: $0) }
        .alert("Delete Bill?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do { try await viewModel.deleteBill(id: billID); dismiss() }
                    catch { mutationError = error.localizedDescription }
                }
            }
        } message: { Text("This removes the bill and its reminders. Expenses already recorded for it are kept.") }
        .alert("Unable to Change Bill", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) {
            Button("OK", role: .cancel) { mutationError = nil }
        } message: { Text(mutationError ?? "") }
        .disabled(viewModel.isSaving)
    }

    private func header(_ bill: BillReminder) -> some View {
        let due = bill.nextDueDate
        let isOverdue = due.map { $0 < Date() } ?? false
        return Section {
            VStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: BillStatus.symbol(due: due, isOverdue: isOverdue),
                               color: BillStatus.color(due: due, isOverdue: isOverdue), large: true)
                VStack(spacing: WalletMetrics.small) {
                    Text(bill.amount.walletFormatted(bill.currencyCode))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(BillStatus.text(due: due, isOverdue: isOverdue))
                        .font(.subheadline)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                }
                if due != nil {
                    Button { paying = bill } label: {
                        Label("Mark as Paid", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WalletMetrics.large)
            .listRowBackground(Color.clear)
        }
    }

    private func details(_ bill: BillReminder) -> some View {
        Section("Details") {
            LabeledContent("Account", value: viewModel.records.account(bill.accountID)?.name ?? "None")
            LabeledContent("Category", value: bill.categoryID == nil ? "None" : viewModel.records.categoryTitle(bill.categoryID))
            LabeledContent("Repeats", value: bill.recurrence?.frequency.rawValue.capitalized ?? "Never")
            LabeledContent("Reminder", value: !bill.notificationsEnabled ? "Off"
                           : bill.reminderDaysBefore == 0 ? "On due date" : "\(bill.reminderDaysBefore) days before")
        }
    }

    private func actions(_ bill: BillReminder) -> some View {
        Section {
            Button { editing = bill } label: {
                Label("Edit Bill", systemImage: "square.and.pencil")
            }
            WalletDestructiveRow(title: "Delete Bill") { confirmingDelete = true }
        }
    }
}

/// Settles the current occurrence on a chosen paid date and adds it as an expense.
private struct BillPaymentView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var bill: BillReminder
    @State private var paidAt = Date()
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    /// Only accounts in the bill's currency can carry the expense.
    private var accounts: [Account] { viewModel.records.accounts.filter { $0.currencyCode == bill.currencyCode } }
    private var canPay: Bool { bill.accountID != nil && bill.categoryID != nil && !viewModel.isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bill", value: bill.name)
                    LabeledContent("Amount") {
                        Text(bill.amount.walletFormatted(bill.currencyCode)).monospacedDigit()
                    }
                    if let due = bill.nextDueDate {
                        LabeledContent("Due", value: due.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                Section {
                    DatePicker("Paid date", selection: $paidAt, in: ...Date(), displayedComponents: .date)
                    BillSelectionRows(records: viewModel.records, accounts: accounts, bill: $bill)
                } header: {
                    Text("Expense")
                } footer: {
                    Text(accounts.isEmpty ? "Add a \(bill.currencyCode) account to record this payment."
                                          : "An expense is added on the paid date. The account and category are saved to this bill.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Mark as Paid")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .disabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Paid") {
                        Task {
                            do { try await viewModel.pay(bill, paidAt: paidAt); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(!canPay)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }
}

private struct BillEditorView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var bill: BillReminder
    @State private var amount = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !viewModel.bills.contains { $0.id == bill.id } }
    private var accounts: [Account] { viewModel.records.accounts.filter { $0.currencyCode == bill.currencyCode } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    LabeledContent("Name") {
                        TextField("Electricity", text: $bill.name)
                            .multilineTextAlignment(.trailing)
                    }
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
                        CurrencyPickerView(selection: $bill.currencyCode, pushed: true)
                    } label: {
                        LabeledContent("Currency", value: bill.currencyCode)
                    }
                }

                Section {
                    BillSelectionRows(records: viewModel.records, accounts: accounts, bill: $bill, categoryRequired: false)
                } header: {
                    Text("Payment")
                } footer: {
                    Text(accounts.isEmpty ? "Add a \(bill.currencyCode) account to save this bill."
                                          : "The account is required. Accounts in the bill's currency are listed.")
                }

                Section("Schedule") {
                    DatePicker("First due date", selection: $bill.dueDate).disabled(bill.nextIndex > 0)
                    RecurrenceFields(rule: $bill.recurrence, start: bill.dueDate)
                }

                Section("Notifications") {
                    Toggle("Remind me", isOn: $bill.notificationsEnabled)
                    if bill.notificationsEnabled {
                        Stepper(bill.reminderDaysBefore == 0 ? "On due date" : "\(bill.reminderDaysBefore) days before",
                                value: $bill.reminderDaysBefore, in: 0...30)
                        Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                        if let message = viewModel.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Bill" : "Edit Bill")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .disabled(viewModel.isSaving)
            .onChange(of: bill.accountID) { _, id in if let account = viewModel.records.account(id) { bill.currencyCode = account.currencyCode } }
            // A different currency invalidates the linked account; pick one in the new currency.
            .onChange(of: bill.currencyCode) { _, code in
                if viewModel.records.account(bill.accountID)?.currencyCode != code { bill.accountID = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do { bill.amount = try AccountAmountInput.parse(amount); try await viewModel.save(bill); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(viewModel.isSaving || bill.accountID == nil)
                }
            }
            .task { amount = bill.amount == 0 ? "" : AccountAmountInput.text(bill.amount) }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}
