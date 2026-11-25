import PhotosUI
import SwiftUI
import WalletDomain

/// Money owed to and by other people, netted per person.
public struct DebtsView: View {
    @ObservedObject private var viewModel: DebtsViewModel
    @State private var editing: Debt?
    @State private var deleting: DebtProgress?
    @State private var settling: DebtProgress?
    @State private var adding: DebtProgress?
    @Environment(\.mainCurrency) private var mainCurrency

    public init(viewModel: DebtsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            ForEach(viewModel.balances) { balance in
                Section {
                    // Each debt opens its own screen, which carries Settle prominently, as a bill's
                    // carries Mark as Paid; the swipe and the menu stay as shortcuts.
                    ForEach(balance.debts) { progress in
                        NavigationLink { DebtDetailView(viewModel: viewModel, debtID: progress.id) } label: {
                            row(progress)
                        }
                        .accessibilityHint("Show debt details")
                        .swipeActions(edge: .leading) {
                            if !progress.isSettled {
                                Button("Settle", systemImage: "checkmark") { settling = progress }
                                    .tint(.green)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = progress }
                        }
                        .contextMenu {
                            if !progress.isSettled {
                                Button("Settle", systemImage: "checkmark") { settling = progress }
                            }
                            Button(progress.debt.direction == .owedToMe ? "Lend More" : "Borrow More",
                                   systemImage: "plus.circle") { adding = progress }
                            Button("Edit", systemImage: "pencil") { editing = progress.debt }
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
        .sheet(item: $adding) { DebtAdditionView(viewModel: viewModel, progress: $0) }
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
            WalletIconTile(symbol: progress.tileSymbol, color: progress.tileColor)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(progress.debt.direction.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(progress.statusText)
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
                    Text("of \(progress.total.walletFormatted(progress.debt.currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // The navigation link draws the chevron.
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .walletListRowPadding(WalletMetrics.tight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Create or edit a debt.
struct DebtEditorView: View {
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
    /// The photo as it will be saved. Only written when `photoChanged`, so an edit that leaves the
    /// photo alone never has to wait for it to load.
    @State private var photoData: Data?
    @State private var photoChanged = false
    @State private var isLoadingPhoto = false
    @State private var isLoadingOriginalPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingPhotoSource = false
    @State private var pickingPhotoFromLibrary = false
    @State private var capturingPhoto = false
    @State private var viewingPhoto = false
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
                    RecordFormRow(symbol: "person") {
                        WalletEditorNavigationButton(title: "Person", value: debt.person.isEmpty ? nil : debt.person) {
                            open(.person)
                        }
                    }
                    // When the money changed hands, which also dates the balance adjustment, if any.
                    RecordFormRow(symbol: "calendar", showsDivider: false) {
                        RecordDateTimeField(date: $debt.createdAt) { focusedField = nil }
                    }
                    moneySection
                    dueDateSection
                    WalletEditorSectionHeader(title: "More Details") { focusedField = nil }
                    RecordFormRow(symbol: "square.and.pencil") {
                        WalletEditorNavigationButton(title: "Note", value: debt.note.isEmpty ? nil : debt.note) {
                            open(.note)
                        }
                    }
                    photoRow
                    if isLoadingPhoto { ProgressView("Preparing photo…").padding(.vertical, 8) }
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
                    // Not while a picked photo is still being prepared, or it would be left out.
                    Button("Save") { save() }.disabled(viewModel.isSaving || isLoadingPhoto)
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
            // Its own task, so a load cut short by pushing a screen is retried on coming back.
            .task { await loadOriginalPhoto() }
            .task(id: photoItem) { await loadPickedPhoto() }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 560)
        #endif
    }

    /// What has been lent or borrowed on this debt since it was made, if anything.
    private var addedSince: Decimal? {
        guard let progress = viewModel.debts.first(where: { $0.debt.id == debt.id }),
              !progress.additions.isEmpty else { return nil }
        return progress.total - progress.debt.amount
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
            // Money added later is its own step, so this amount stays the first one.
            if let added = addedSince {
                Text("First amount. \(added.walletFormatted(debt.currencyCode)) more was "
                     + (debt.direction == .owedToMe ? "lent" : "borrowed") + " later; see the debt's history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Whether the money changed hands when the debt was made. Recorded as a balance adjustment, so
    /// the balance is right while the loan counts as neither spending nor income; settling records
    /// its return the same way. Both rows lead with a tile, as the record editor's account row does.
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
        RecordFormRow(symbol: "calendar.badge.clock", showsDivider: hasDueDate) {
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

    /// One photo per debt, as a record has: a receipt, a signed IOU, a transfer screenshot. An empty
    /// row asks where it should come from; a filled one opens it, which is where it can be deleted.
    private var photoRow: some View {
        RecordFormRow(symbol: "photo", showsDivider: false) {
            WalletEditorNavigationButton(title: "Photo", value: photoData == nil ? "None" : "1") {
                focusedField = nil
                if photoData == nil { choosingPhotoSource = true } else { viewingPhoto = true }
            }
            .disabled(isLoadingPhoto || isLoadingOriginalPhoto)
        }
        .confirmationDialog("Add Photo", isPresented: $choosingPhotoSource, titleVisibility: .visible) {
            if RecordCameraAvailability.isAvailable {
                Button("Take Photo") { capturingPhoto = true }
            }
            Button("Choose from Library") { pickingPhotoFromLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $pickingPhotoFromLibrary, selection: $photoItem, matching: .images)
        .sheet(isPresented: $viewingPhoto) {
            if let photoData {
                RecordPhotoViewer(data: photoData) {
                    self.photoData = nil
                    photoChanged = true
                    photoItem = nil
                }
            }
        }
        #if os(iOS)
            .fullScreenCover(isPresented: $capturingPhoto) {
                RecordCameraPicker(
                    onCapture: { data in Task { await applyPhoto(data) } },
                    onError: { errorMessage = $0 })
                    .ignoresSafeArea()
            }
        #endif
    }

    /// Reads an existing debt's photo so the row can show and open it.
    private func loadOriginalPhoto() async {
        guard debt.hasPhoto, photoData == nil, !photoChanged else { return }
        isLoadingOriginalPhoto = true
        defer { isLoadingOriginalPhoto = false }
        do {
            let data = try await viewModel.photo(id: debt.id)
            try Task.checkCancellation()
            if !photoChanged { photoData = data }
        } catch is CancellationError {
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadPickedPhoto() async {
        guard let item = photoItem else {
            isLoadingPhoto = false
            return
        }
        isLoadingPhoto = true
        defer { if item == photoItem { isLoadingPhoto = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw RecordValidationError.invalidPhoto
            }
            try Task.checkCancellation()
            if item == photoItem { await applyPhoto(data) }
        } catch is CancellationError {
        } catch { if item == photoItem { errorMessage = error.localizedDescription } }
    }

    /// Shrinks a picked or freshly taken photo on the record editor's path, so both are stored alike.
    private func applyPhoto(_ data: Data) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            photoData = try await Task.detached { try RecordPhoto.prepare(data) }.value
            photoChanged = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
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
                try await viewModel.save(value, moneyMovedThrough: movingThrough,
                                         photo: photoChanged ? .replace(photoData) : .keep)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
