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
    @State private var errorMessage: String?
    @State private var choosingCurrency = false
    @State private var choosingSymbol = false
    @Environment(\.defaultCurrency) private var defaultCurrency

    init(viewModel: AccountsViewModel, account: Account? = nil) {
        self.viewModel = viewModel
        self.account = account
        let settings = account?.settings ?? AccountSettings()
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .cash)
        // A new account takes the default currency on appear; the environment isn't readable here.
        _currencyCode = State(initialValue: account?.currencyCode ?? "")
        _settings = State(initialValue: settings)
        // Nothing to show is left empty so the field's "0" reads as the placeholder it is, rather
        // than as a zero the person has to clear before typing.
        _balanceText = State(initialValue: settings.currentBalance == 0 ? ""
            : AccountAmountInput.text(settings.currentBalance))
        _minimumText = State(initialValue: AccountAmountInput.text(settings.minimumBalance))
        _maximumText = State(initialValue: AccountAmountInput.text(settings.maximumBalance))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Label leading and the field trailing, like Currency, Balance and Type below it
                    // and the Name row in the category and label editors.
                    HStack(spacing: 16) {
                        Text("Name")
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Name")
                    }
                    .onAppear { if currencyCode.isEmpty { currencyCode = defaultCurrency } }
                    if account == nil {
                        // Reads as the row it is — a label, the choice, and somewhere to go —
                        // rather than as a line of button-tinted text.
                        Button { choosingCurrency = true } label: {
                            HStack {
                                Text("Currency").foregroundStyle(.primary)
                                Spacer()
                                Text(currencyCode).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        // Without this the form tints the whole label, and the row reads as a line
                        // of blue text rather than as a setting with a value.
                        .buttonStyle(.plain)
                    } else {
                        LabeledContent("Currency", value: currencyCode)
                    }
                    // The opening amount is the number people check before saving, so it is set in
                    // the rounded balance type the dashboard total uses. The currency is chosen a
                    // row above, so it is not repeated here.
                    LabeledContent("Balance") {
                        WalletAmountField(amount: balanceText) {
                            TextField("", text: $balanceText.groupedAmount())
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                                .accessibilityLabel("Balance in \(currencyCode)")
                        }
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    }
                    WalletMenuPicker("Type", selection: $type, value: type.title) {
                        ForEach(AccountType.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    Button { choosingSymbol = true } label: {
                        LabeledContent("Icon") {
                            HStack(spacing: WalletMetrics.small) {
                                // Follows the type being edited until an icon is chosen.
                                WalletIconTile(symbol: settings.symbol ?? type.symbol, color: settings.color.tint)
                                WalletDisclosure()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Account")
                } footer: {
                    if account == nil {
                        Text("Currency is chosen once when you create an account. Enter amounts using your local decimal separator; thousands are grouped for you. Leave the balance empty to open the account at zero.")
                    } else {
                        Text("Changing the balance records the difference as a balance adjustment dated now, so earlier history stays as it was. To choose the date or add a note, use Adjust Balance on the account.")
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                        ForEach(AccountColor.allCases) { color in
                            Button { settings.color = color } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(color.tint)
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if settings.color == color {
                                                Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                            }
                                        }
                                    Text(color.title).font(.caption).foregroundStyle(.primary)
                                }
                                .frame(minWidth: 44, minHeight: 60)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.title)
                            .accessibilityAddTraits(settings.color == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Balance below limit", isOn: $settings.notifyBelowMinimum)
                    if settings.notifyBelowMinimum {
                        WalletAmountField(amount: minimumText, placeholder: "Minimum balance (\(currencyCode))",
                                          alignment: .leading) {
                            TextField("", text: $minimumText.groupedAmount())
                                .accessibilityLabel("Minimum balance in \(currencyCode)")
                        }
                    }
                    Toggle("Balance above limit", isOn: $settings.notifyAboveMaximum)
                    if settings.notifyAboveMaximum {
                        WalletAmountField(amount: maximumText, placeholder: "Maximum balance (\(currencyCode))",
                                          alignment: .leading) {
                            TextField("", text: $maximumText.groupedAmount())
                                .accessibilityLabel("Maximum balance in \(currencyCode)")
                        }
                    }
                } header: {
                    Text("In-app notifications")
                } footer: {
                    Text("An alert appears in Accounts while the balance is below your minimum or above your maximum. Alerts clear when the balance returns within your limits.")
                }

                Section {
                    Toggle("Exclude from stats", isOn: $settings.excludeFromStats)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Keep this account visible while excluding it from statistics. Balance alerts remain active.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).accessibilityLabel("Error: \(errorMessage)") }
                }
            }
            .formStyle(.grouped)
            .disabled(viewModel.isSaving)
            .navigationTitle(account == nil ? "Create Account" : "Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text(account == nil ? "Create" : "Save") }
                    }
                    .disabled(viewModel.isSaving || trimmedName.isEmpty || trimmedName.count > 80)
                }
            }
            .sheet(isPresented: $choosingCurrency) { CurrencyPickerView(selection: $currencyCode) }
            .sheet(isPresented: $choosingSymbol) {
                AccountSymbolPicker(name: trimmedName.isEmpty ? "New account" : trimmedName,
                                    type: type, color: settings.color.tint, selection: $settings.symbol)
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 680)
        #endif
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
