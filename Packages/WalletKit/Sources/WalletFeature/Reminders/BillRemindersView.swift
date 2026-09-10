import SwiftUI
import WalletDomain

struct BillRemindersView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: BillReminder?
    @State private var paying: BillReminder?
    @State private var deleting: BillReminder?
    @State private var calendarMode = false
    @State private var selectedDate = Date()

    var body: some View {
        List {
            Toggle("Calendar view", isOn: $calendarMode)
            if calendarMode { DatePicker("Select a day", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical) }
            if viewModel.bills.isEmpty { Text("Add bills to track due dates and payment reminders.") }
            ForEach(viewModel.bills.filter { !calendarMode || $0.nextDueDate.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } == true }) { bill in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(bill.name).font(.headline)
                        Spacer()
                        Text(bill.amount, format: .currency(code: bill.currencyCode))
                    }
                    if let due = bill.nextDueDate {
                        Text("\(due < Date() ? "Overdue" : "Due") · \(due.formatted())")
                            .font(.subheadline).foregroundStyle(due < Date() ? .red : .secondary)
                        Button("Mark as Paid") { paying = bill }.buttonStyle(.bordered)
                    } else { Text("Paid / complete").font(.caption).foregroundStyle(.secondary) }
                    Button("Edit") { editing = bill }
                }
                .swipeActions { Button("Delete", role: .destructive) { deleting = bill } }
                .contextMenu { Button("Delete", role: .destructive) { deleting = bill } }
            }
        }
        .navigationTitle("Bills")
        .toolbar { Button("Add Bill", systemImage: "plus") { editing = BillReminder() } }
        .sheet(item: $editing) { BillEditorView(viewModel: viewModel, bill: $0) }
        .confirmationDialog("Mark this bill occurrence as paid?", isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } }), titleVisibility: .visible) {
            Button("Mark Paid and Add Expense") { pay(createRecord: true) }
                .disabled(paying?.accountID == nil || paying?.categoryID == nil)
            Button("Mark Paid Only") { pay(createRecord: false) }
            Button("Cancel", role: .cancel) { paying = nil }
        } message: { Text("Add Expense creates one record using the linked account/category. Mark Paid Only leaves balances unchanged.") }
        .alert("Delete Bill Reminder?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let bill = deleting else { return }
                Task { do { try await viewModel.deleteBill(id: bill.id) } catch { viewModel.errorMessage = error.localizedDescription } }
            }
        } message: { Text("Existing payment records are kept.") }
        .disabled(viewModel.isSaving)
    }

    private func pay(createRecord: Bool) {
        guard let bill = paying else { return }
        paying = nil
        Task { do { try await viewModel.pay(bill, createRecord: createRecord) } catch { viewModel.errorMessage = error.localizedDescription } }
    }
}

private struct BillEditorView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var bill: BillReminder
    @State private var amount = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Bill name", text: $bill.name)
                TextField("Amount", text: $amount)
                Picker("Currency", selection: $bill.currencyCode) {
                    ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
                }.disabled(bill.accountID != nil)
                Picker("Account", selection: $bill.accountID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.records.accounts) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Category", selection: $bill.categoryID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.records.categories) { Text(viewModel.records.categoryTitle($0.id)).tag(Optional($0.id)) }
                }
                DatePicker("First due date", selection: $bill.dueDate).disabled(bill.nextIndex > 0)
                RecurrenceFields(rule: $bill.recurrence, start: bill.dueDate)
                Toggle("Notifications", isOn: $bill.notificationsEnabled)
                if bill.notificationsEnabled {
                    Stepper(bill.reminderDaysBefore == 0 ? "On due date" : "\(bill.reminderDaysBefore) days before", value: $bill.reminderDaysBefore, in: 0...30)
                    Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                    if let message = viewModel.errorMessage { Text(message).foregroundStyle(.red) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Bill Reminder")
            .disabled(viewModel.isSaving)
            .onChange(of: bill.accountID) { _, id in if let account = viewModel.records.account(id) { bill.currencyCode = account.currencyCode } }
            .toolbar {
                Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                Button("Save") {
                    Task {
                        do { bill.amount = try AccountAmountInput.parse(amount); try await viewModel.save(bill); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(viewModel.isSaving)
            }
            .task { amount = bill.amount == 0 ? "" : AccountAmountInput.text(bill.amount) }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}
