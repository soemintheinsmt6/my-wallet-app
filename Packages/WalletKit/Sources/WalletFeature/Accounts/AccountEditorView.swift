import SwiftUI
import WalletDomain

struct AccountEditorView: View {
    @ObservedObject var viewModel: AccountsViewModel
    let account: Account?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var type: AccountType
    @State private var currencyCode: String
    @State private var settings: AccountSettings
    @State private var balanceText: String
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var accountNumberText: String
    @State private var errorMessage: String?
    @State private var screen: Screen?
    @State private var choosingSymbol = false
    @State private var confirmingDeletion = false
    @State private var wasDeleted = false
    @FocusState private var focusedField: Field?
    @Environment(\.mainCurrency) private var mainCurrency
    /// Called after the account is deleted from here, once this editor has closed.
    private let onDeleted: () -> Void

    private enum Field: Hashable { case balance, accountNumber, minimum, maximum }
    private enum Screen: Hashable { case currency, name, color }

    init(viewModel: AccountsViewModel, account: Account? = nil, onDeleted: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.account = account
        self.onDeleted = onDeleted
        let settings = account?.settings ?? AccountSettings()
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .cash)
        // A new account takes the main currency on appear; the environment isn't readable here.
        _currencyCode = State(initialValue: account?.currencyCode ?? "")
        _settings = State(initialValue: settings)
        // Nothing to show is left empty so the field's "0" reads as the placeholder it is, rather
        // than as a zero the person has to clear before typing.
        _balanceText = State(initialValue: settings.currentBalance == 0 ? ""
            : AccountAmountInput.text(settings.currentBalance))
        // Likewise for the limits: an unset limit shows "0" as a placeholder, not as typed text.
        _minimumText = State(initialValue: settings.minimumBalance == 0 ? ""
            : AccountAmountInput.text(settings.minimumBalance))
        _maximumText = State(initialValue: settings.maximumBalance == 0 ? ""
            : AccountAmountInput.text(settings.maximumBalance))
        _accountNumberText = State(initialValue: settings.accountNumber ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Follows the type being edited until an icon is chosen.
    private var symbol: String { settings.symbol ?? type.symbol }

    var body: some View {
        NavigationStack {
            // The record editor's layout: the balance on top, then rows.
            ScrollView {
                VStack(spacing: 0) {
                    balanceSection
                    generalSection
                    appearanceSection
                    alertsSection
                    statisticsSection
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding(20)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                    // Last, like Delete Record in the record editor. Opens the same sheet as swiping
                    // an account, which shows what happens to its records before anything is deleted.
                    if account != nil {
                        WalletEditorDeleteButton(title: "Delete Account") {
                            focusedField = nil
                            confirmingDeletion = true
                        }
                    }
                }
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .disabled(viewModel.isSaving)
            .navigationTitle(account == nil ? "Create Account" : "Edit Account")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .currency:
                    CurrencyPickerView(selection: $currencyCode, pushed: true)
                case .name:
                    RecordTextEntry(title: "Name", text: $name, caption: "Name this account")
                case .color:
                    AccountColorSelection(symbol: symbol, selection: $settings.color)
                }
            }
            // Pinned at the bottom like the record editor's Save, rather than in the toolbar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WalletEditorBottomButton(
                    title: account == nil ? "Create" : "Save", isBusy: viewModel.isSaving,
                    isEnabled: !viewModel.isSaving && !trimmedName.isEmpty && trimmedName.count <= 80
                ) { Task { await save() } }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
            }
            .task { if currencyCode.isEmpty { currencyCode = mainCurrency } }
            .sheet(isPresented: $choosingSymbol) {
                AccountSymbolPicker(name: trimmedName.isEmpty ? "New account" : trimmedName,
                                    type: type, color: settings.color.tint, selection: $settings.symbol)
            }
            // Closes only after the deletion sheet has gone, so the two never dismiss at once.
            .sheet(isPresented: $confirmingDeletion, onDismiss: closeIfDeleted) {
                if let account {
                    AccountDeletionView(viewModel: viewModel, account: account) { wasDeleted = true }
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 680)
        #endif
    }

    /// The balance is the number people check before saving, so it leads, large. The currency is
    /// chosen once, when the account is created: only then is its chip a button.
    @ViewBuilder private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            RecordAmountField(
                sign: "", color: .primary, label: "Balance in \(currencyCode)",
                currency: currencyCode, amount: $balanceText, focus: $focusedField, field: .balance,
                chooseCurrency: account == nil ? { open(.currency) } : nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        WalletEditorCaption(account == nil ? Self.newBalanceCaption : Self.editBalanceCaption)
    }

    private static let newBalanceCaption = "Currency is chosen once, when you create the account. "
        + "Leave the balance empty to open the account at zero."
    private static let editBalanceCaption = "Changing the balance records the difference as a balance adjustment "
        + "dated now, so earlier history stays as it was. To choose the date or add a note, use Adjust Balance on the account."
    private static let accountNumberCaption = "Shown as •••• and the last four characters everywhere but here; "
        + "tap it on the account to copy the full number. It syncs end-to-end encrypted through iCloud and is included in JSON backups."
    private static let alertsCaption = "An alert appears in Accounts while the balance is below your minimum or above "
        + "your maximum. Alerts clear when the balance returns within your limits."

    @ViewBuilder private var generalSection: some View {
        WalletEditorSectionHeader(title: "General") { focusedField = nil }
        RecordFormRow(symbol: "square.and.pencil") {
            WalletEditorNavigationButton(title: "Name", value: trimmedName.isEmpty ? nil : trimmedName) {
                open(.name)
            }
        }
        RecordFormRow(symbol: type.symbol, showsDivider: type.hasAccountNumber) {
            WalletMenuPicker("Type", selection: $type, value: type.title) {
                ForEach(AccountType.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        }
        // Follows the type being edited: cash has no number, so the row leaves with it. Typed in
        // place rather than on its own screen, for the card or plain keyboard it needs.
        if type.hasAccountNumber {
            RecordFormRow(symbol: "number", showsDivider: false) {
                HStack(spacing: 16) {
                    Text(type.accountNumberTitle)
                    TextField("Optional", text: $accountNumberText)
                        .focused($focusedField, equals: .accountNumber)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(type == .creditCard ? .numberPad : .asciiCapable)
                            .textContentType(type == .creditCard ? .creditCardNumber : nil)
                        #endif
                        .accessibilityLabel(type.accountNumberTitle)
                }
            }
            WalletEditorCaption(Self.accountNumberCaption)
        }
    }

    /// Both rows lead with a tile in the account's color, so the section's icons match.
    @ViewBuilder private var appearanceSection: some View {
        WalletEditorSectionHeader(title: "Appearance") { focusedField = nil }
        RecordFormRow(symbol: symbol, color: settings.color.tint, filledIcon: true) {
            WalletEditorNavigationButton(title: "Icon", value: nil) {
                focusedField = nil
                choosingSymbol = true
            }
        }
        // A choice like Category in the record editor: the row names it, its own screen lists them.
        RecordFormRow(symbol: "paintpalette.fill", color: settings.color.tint, filledIcon: true,
                      showsDivider: false) {
            WalletEditorNavigationButton(title: "Color", value: settings.color.title) { open(.color) }
        }
    }

    /// Each limit's amount sits on its switch's row, as the repeat rows keep their values.
    @ViewBuilder private var alertsSection: some View {
        WalletEditorSectionHeader(title: "Balance Alerts") { focusedField = nil }
        RecordFormRow(symbol: "arrow.down.to.line") {
            limitField("Balance below limit", isOn: $settings.notifyBelowMinimum, title: "Minimum",
                       text: $minimumText, field: .minimum)
        }
        RecordFormRow(symbol: "arrow.up.to.line", showsDivider: false) {
            limitField("Balance above limit", isOn: $settings.notifyAboveMaximum, title: "Maximum",
                       text: $maximumText, field: .maximum)
        }
        WalletEditorCaption(Self.alertsCaption)
    }

    private func limitField(_ label: String, isOn: Binding<Bool>, title: String,
                            text: Binding<String>, field: Field) -> some View {
        VStack(spacing: WalletMetrics.small) {
            Toggle(label, isOn: isOn.animation())
            if isOn.wrappedValue {
                HStack {
                    Text(title).foregroundStyle(.secondary)
                    Spacer()
                    WalletAmountField(amount: text.wrappedValue) {
                        TextField("", text: text.groupedAmount())
                            .focused($focusedField, equals: field)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                            .accessibilityLabel("\(title) balance in \(currencyCode)")
                    }
                    .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder private var statisticsSection: some View {
        WalletEditorSectionHeader(title: "Statistics") { focusedField = nil }
        RecordFormRow(symbol: "chart.pie", showsDivider: false) {
            Toggle("Exclude from stats", isOn: $settings.excludeFromStats)
        }
        WalletEditorCaption("Keep this account visible while excluding it from statistics. Balance alerts remain active.")
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
    }

    /// After the deletion sheet closes, closes this editor too if the account was deleted.
    private func closeIfDeleted() {
        guard wasDeleted else { return }
        onDeleted()
        dismiss()
    }

    private func save() async {
        errorMessage = nil
        do {
            var values = settings
            values.currentBalance = try AccountAmountInput.parseAllowingEmpty(balanceText)
            if values.notifyBelowMinimum {
                values.minimumBalance = try AccountAmountInput.parseAllowingEmpty(minimumText)
            }
            if values.notifyAboveMaximum {
                values.maximumBalance = try AccountAmountInput.parseAllowingEmpty(maximumText)
            }
            // Trimmed and checked when saved; dropped there if the type is cash.
            values.accountNumber = accountNumberText
            if let account {
                try await viewModel.update(id: account.id, name: name, type: type, settings: values)
            } else {
                try await viewModel.create(name: name, type: type, currencyCode: currencyCode, settings: values)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The account colors as a list, like the record editor's account and category pickers. Each row
/// shows the account's own icon in that color, so the choice is seen as it will look.
private struct AccountColorSelection: View {
    let symbol: String
    @Binding var selection: AccountColor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(AccountColor.allCases) { color in
            Button {
                selection = color
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    WalletIconTile(symbol: symbol, color: color.tint)
                    Text(color.title).foregroundStyle(.primary)
                    Spacer()
                    if selection == color { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == color ? .isSelected : [])
            .walletFirstRow(color == AccountColor.allCases.first)
        }
        .listStyle(.plain)
        .navigationTitle("Color")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
