import SwiftUI
import WalletDomain

struct BillRemindersView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State private var editing: BillReminder?
    @State private var paying: BillReminder?
    @State private var deleting: BillReminder?
    @State private var calendarMode = false
    @State private var selectedDate = Date()
    @Environment(\.mainCurrency) private var mainCurrency

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
                .labelsHidden()
                .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                          bottom: WalletMetrics.small, trailing: WalletMetrics.large))
                .listRowSeparator(.hidden)
                if calendarMode {
                    DatePicker("Select a day", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .listRowSeparator(.hidden)
                }
            }
            // Controls above the list, not rows of it.
            .listSectionSeparator(.hidden)

            Section {
                if sortedBills.isEmpty {
                    Text(calendarMode ? "No bills due on this day." : "Add bills to track due dates and payment reminders.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedBills) { bill in row(bill) }
            } header: {
                // The page is already titled Bills; only the calendar's chosen day needs saying.
                if calendarMode { Text(selectedDate.formatted(date: .abbreviated, time: .omitted)) }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Bills")
        .toolbar { Button("Add Bill", systemImage: "plus") { editing = BillReminder(currencyCode: mainCurrency) } }
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

    /// Tapping opens the bill, whose screen leads with Mark as Paid.
    private func row(_ bill: BillReminder) -> some View {
        let due = bill.nextDueDate
        let isOverdue = due.map { $0 < Date() } ?? false
        return NavigationLink { BillDetailView(viewModel: viewModel, billID: bill.id) } label: {
            // Laid out like a record row: the category's tile, name over due date, and the amount
            // trailing as the expense paying it records. Paying leads the bill's own screen, as
            // Settle leads a debt's; the swipe and the menu stay as shortcuts.
            HStack(spacing: WalletMetrics.medium) {
                if let category = viewModel.records.category(bill.categoryID) {
                    CategoryIcon(category: category)
                } else {
                    WalletIconTile(symbol: BillStatus.symbol(due: due, isOverdue: isOverdue),
                                   color: BillStatus.color(due: due, isOverdue: isOverdue))
                }
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text(bill.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(BillStatus.text(due: due, isOverdue: isOverdue))
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: WalletMetrics.small)
                // A finished bill owes nothing more, so it drops the expense sign and color.
                WalletAmountText(amount: bill.amount, currencyCode: bill.currencyCode,
                                 kind: due == nil ? nil : .expense)
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
                // Flat, with the editors' band headings, like the category details.
                List {
                    header(bill)
                    details(bill)
                    actions(bill)
                }
                .listStyle(.plain)
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
        return Group {
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
                    // The same action button as a debt's Settle.
                    WalletActionButton(title: "Mark as Paid", tint: isOverdue ? .red : .green) { paying = bill }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WalletMetrics.large)
            .listRowSeparator(.hidden)
        }
    }

    /// Every row leads with a tile, so the section's icons match: the account's and category's
    /// own, and Planning's recurring and reminder colors for the schedule. Rows under a band row
    /// rather than a section with a header, so the space under the last row matches the space
    /// above the first (see `WalletListSectionHeader`).
    @ViewBuilder private func details(_ bill: BillReminder) -> some View {
        let account = viewModel.records.account(bill.accountID)
        let category = viewModel.records.category(bill.categoryID)
        WalletListSectionHeader("Details")
        Group {
            WalletListValueRow(title: "Account", value: account?.name ?? "None") {
                WalletIconTile(symbol: account?.symbol ?? WalletSymbols.walletFill,
                               color: account?.settings.color.tint ?? .gray)
            }
            WalletListValueRow(title: "Category", value: category?.name ?? "None") {
                if let category { CategoryIcon(category: category) } else { WalletIconTile(symbol: "questionmark") }
            }
            WalletListValueRow(title: "Repeats", value: bill.recurrence?.frequency.rawValue.capitalized ?? "Never") {
                WalletIconTile(symbol: "repeat", color: .indigo)
            }
            WalletListValueRow(title: "Reminder", value: !bill.notificationsEnabled ? "Off"
                               : bill.reminderDaysBefore == 0 ? "On due date" : "\(bill.reminderDaysBefore) days before") {
                WalletIconTile(symbol: "bell.fill", color: .purple)
            }
            // The band below separates the groups, so the last row draws no rule of its own.
            .listRowSeparator(.hidden, edges: .bottom)
        }
    }

    @ViewBuilder private func actions(_ bill: BillReminder) -> some View {
        WalletListSectionHeader("Manage")
        Group {
            Button { editing = bill } label: {
                Label("Edit Bill", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            WalletDestructiveRow(title: "Delete Bill") { confirmingDelete = true }
                .listRowSeparator(.hidden, edges: .bottom)
        }
    }
}

/// Settles the current occurrence on a chosen paid date and adds it as an expense.
private struct BillPaymentView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var bill: BillReminder
    @State private var paidAt = Date()
    @State private var error: String?
    @State private var screen: Screen?
    @Environment(\.dismiss) private var dismiss

    private enum Screen: Hashable { case account, category }

    /// Only accounts in the bill's currency can carry the expense.
    private var accounts: [Account] { viewModel.records.accounts.filter { $0.currencyCode == bill.currencyCode } }
    private var canPay: Bool { bill.accountID != nil && bill.categoryID != nil && !viewModel.isSaving }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the expense it adds on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    expenseSection
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
                .walletEditorRows()
            }
            .walletEditorPage()
            .navigationTitle("Mark as Paid")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .account:
                    RecordAccountSelection(accounts: accounts, selection: $bill.accountID, title: "Account")
                case .category:
                    RecordCategoryPicker(viewModel: viewModel.records, kind: .expense, selection: $bill.categoryID) {
                        self.screen = nil
                    }
                }
            }
            .disabled(viewModel.isSaving)
            // Pinned at the bottom like the record editor's Save.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WalletEditorBottomButton(title: "Mark as Paid", isBusy: viewModel.isSaving, isEnabled: canPay) {
                    Task {
                        do { try await viewModel.pay(bill, paidAt: paidAt); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    /// The bill and when it was due, over the expense paying it adds: the bill's full amount, red
    /// with a minus as an expense is in the record editor, shown rather than typed.
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            RecordAmountLabel(sign: "−", color: .red, currency: bill.currencyCode, amount: bill.amount)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var caption: String {
        guard let due = bill.nextDueDate else { return bill.name }
        return "\(bill.name) · due \(due.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Every row leads with a tile, so the section's icons match: the paid date's, the record
    /// editor's wallet, and the chosen category's.
    @ViewBuilder private var expenseSection: some View {
        WalletEditorSectionHeader(title: "Expense")
        RecordFormRow(symbol: "calendar", color: .red, filledIcon: true) {
            DatePicker("Paid date", selection: $paidAt, in: ...Date(), displayedComponents: .date)
        }
        RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true) {
            WalletEditorNavigationButton(title: "Account",
                                         value: viewModel.records.account(bill.accountID)?.name ?? "Choose") {
                screen = .account
            }
        }
        RecordFormRow(symbol: "questionmark", category: viewModel.records.category(bill.categoryID),
                      categoryTile: true, showsDivider: false) {
            // The chosen category or subcategory by its own name, without its parent.
            WalletEditorNavigationButton(title: "Category",
                                         value: viewModel.records.category(bill.categoryID)?.name ?? "Choose") {
                screen = .category
            }
        }
        WalletEditorCaption(accounts.isEmpty
            ? "Add a \(bill.currencyCode) account to record this payment."
            : "An expense is added on the paid date. The account and category are saved to this bill.")
    }
}

private struct BillEditorView: View {
    @ObservedObject var viewModel: PlanningViewModel
    @State var bill: BillReminder
    @State private var amount = ""
    @State private var error: String?
    @State private var screen: Screen?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case amount }
    private enum Screen: Hashable { case currency, name, account, category }

    private var isNew: Bool { !viewModel.bills.contains { $0.id == bill.id } }
    private var accounts: [Account] { viewModel.records.accounts.filter { $0.currencyCode == bill.currencyCode } }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the amount on top, then rows. Deleting stays on the bill's
            // own screen, which this editor is opened from.
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    generalSection
                    scheduleSection
                    notificationsSection
                    if let error { Text(error).foregroundStyle(.red).padding(20) }
                }
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
                .walletEditorRows()
            }
            .scrollDismissesKeyboard(.immediately)
            .walletEditorPage()
            .navigationTitle(isNew ? "New Bill" : "Edit Bill")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .currency:
                    CurrencyPickerView(selection: $bill.currencyCode, pushed: true)
                case .name:
                    RecordTextEntry(title: "Name", text: $bill.name, caption: "What is this bill for?")
                case .account:
                    RecordAccountSelection(accounts: accounts, selection: $bill.accountID, title: "Account")
                case .category:
                    RecordCategoryPicker(viewModel: viewModel.records, kind: .expense,
                                         selection: $bill.categoryID) { self.screen = nil }
                }
            }
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
                    }.disabled(viewModel.isSaving || bill.accountID == nil || bill.categoryID == nil)
                }
            }
            .task {
                // Runs again on returning from a pushed screen; only the first appearance loads.
                guard !didLoad else { return }
                didLoad = true
                amount = bill.amount == 0 ? "" : AccountAmountInput.text(bill.amount)
                if isNew {
                    await Task.yield()
                    focusedField = .amount
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    /// Red with a minus, as an expense is in the record editor, since paying it records one.
    private var amountSection: some View {
        RecordAmountField(
            sign: "−", color: .red, label: "Bill amount",
            currency: bill.currencyCode, amount: $amount, focus: $focusedField, field: .amount
        ) { open(.currency) }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Name, account and category all lead with a tile, so the section's icons match: the bill's
    /// own orange calendar from Planning, the record editor's wallet, and the chosen category.
    @ViewBuilder private var generalSection: some View {
        WalletEditorSectionHeader(title: "General") { focusedField = nil }
        RecordFormRow(symbol: "calendar.badge.clock", color: .orange, filledIcon: true) {
            WalletEditorNavigationButton(title: "Name", value: bill.name.isEmpty ? nil : bill.name) { open(.name) }
        }
        RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true) {
            WalletEditorNavigationButton(title: "Account",
                                         value: viewModel.records.account(bill.accountID)?.name ?? "Choose") {
                open(.account)
            }
        }
        RecordFormRow(symbol: "questionmark", category: viewModel.records.category(bill.categoryID),
                      categoryTile: true, showsDivider: false) {
            // The chosen category or subcategory by its own name, without its parent.
            WalletEditorNavigationButton(title: "Category",
                                         value: viewModel.records.category(bill.categoryID)?.name ?? "Choose") {
                open(.category)
            }
        }
        WalletEditorCaption(accounts.isEmpty ? "Add a \(bill.currencyCode) account to save this bill."
                                             : "Account and category are required. Accounts in the bill's currency are listed.")
    }

    @ViewBuilder private var scheduleSection: some View {
        WalletEditorSectionHeader(title: "Schedule") { focusedField = nil }
        RecordFormRow(symbol: "calendar") {
            DatePicker("First due date", selection: $bill.dueDate).disabled(bill.nextIndex > 0)
        }
        RecurrenceFields(rule: $bill.recurrence, start: bill.dueDate, style: .rows)
    }

    @ViewBuilder private var notificationsSection: some View {
        let asksPermission = bill.notificationsEnabled && !viewModel.notificationsAuthorized
        WalletEditorSectionHeader(title: "Notifications") { focusedField = nil }
        RecordFormRow(symbol: "bell", showsDivider: bill.notificationsEnabled) {
            Toggle("Remind me", isOn: $bill.notificationsEnabled)
        }
        .refreshesNotificationAuthorization { await viewModel.refreshNotificationAuthorization() }
        if bill.notificationsEnabled {
            RecordFormRow(symbol: "clock", showsDivider: asksPermission) {
                Text(bill.reminderDaysBefore == 0 ? "On due date" : "\(bill.reminderDaysBefore) days before")
                Spacer()
                Stepper("Days before", value: $bill.reminderDaysBefore, in: 0...30).labelsHidden()
            }
            if asksPermission {
                RecordFormRow(symbol: "bell.badge", color: .accentColor, showsDivider: false) {
                    Button("Enable System Notifications") { Task { await viewModel.requestNotifications() } }
                    Spacer()
                }
            }
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
    }
}
