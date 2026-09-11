import SwiftUI
import WalletDomain

struct BillRemindersView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: BillReminder?
    @State private var paying: BillReminder?
    @State private var deleting: BillReminder?
    @State private var calendarMode = false
    @State private var selectedDate = Date()

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

    private func row(_ bill: BillReminder) -> some View {
        let due = bill.nextDueDate
        let isOverdue = due.map { $0 < Date() } ?? false
        return Button { editing = bill } label: {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: due == nil ? "checkmark.circle" : isOverdue ? "exclamationmark.circle" : "calendar",
                               color: due == nil ? .green : isOverdue ? .red : .orange)
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text(bill.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(status(due: due, isOverdue: isOverdue))
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: WalletMetrics.small)
                Text(bill.amount.walletFormatted(bill.currencyCode))
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
        .accessibilityHint("Edit bill")
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

    private func status(due: Date?, isOverdue: Bool) -> String {
        guard let due else { return "Paid · complete" }
        let when = due.formatted(date: .abbreviated, time: .omitted)
        return isOverdue ? "Overdue · \(when)" : "Due \(when)"
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

    private var isNew: Bool { !viewModel.bills.contains { $0.id == bill.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    LabeledContent("Name") {
                        TextField("Electricity", text: $bill.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Amount") {
                        TextField("0", text: $amount.groupedAmount())
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                    }
                    Picker("Currency", selection: $bill.currencyCode) {
                        ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(bill.accountID != nil)
                }

                Section {
                    Picker("Account", selection: $bill.accountID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(viewModel.records.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Category", selection: $bill.categoryID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(viewModel.records.categories) { Text(viewModel.records.categoryTitle($0.id)).tag(Optional($0.id)) }
                    }
                } header: {
                    Text("Payment")
                } footer: {
                    Text("Both are required to create an expense when marking this bill paid. The currency follows the linked account.")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do { bill.amount = try AccountAmountInput.parse(amount); try await viewModel.save(bill); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(viewModel.isSaving)
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
