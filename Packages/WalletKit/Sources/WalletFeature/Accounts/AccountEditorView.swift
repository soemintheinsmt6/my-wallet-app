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

    init(viewModel: AccountsViewModel, account: Account? = nil) {
        self.viewModel = viewModel
        self.account = account
        let settings = account?.settings ?? AccountSettings()
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .cash)
        _currencyCode = State(initialValue: account?.currencyCode ?? Locale.current.currency?.identifier ?? "USD")
        _settings = State(initialValue: settings)
        _balanceText = State(initialValue: AccountAmountInput.text(settings.currentBalance))
        _minimumText = State(initialValue: AccountAmountInput.text(settings.minimumBalance))
        _maximumText = State(initialValue: AccountAmountInput.text(settings.maximumBalance))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if account == nil {
                        Button { choosingCurrency = true } label: {
                            LabeledContent("Currency", value: currencyCode)
                        }
                    } else {
                        LabeledContent("Currency", value: currencyCode)
                    }
                    // The opening amount is the number people check before saving, so it gets the
                    // trailing alignment and larger type the record amount field uses, scaled down
                    // to fit a form row.
                    LabeledContent {
                        TextField("0", text: $balanceText.groupedAmount())
                            .multilineTextAlignment(.trailing)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                            .accessibilityLabel("Current balance in \(currencyCode)")
                    } label: {
                        Text("Current balance")
                        Text(currencyCode)
                    }
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Currency is chosen once when you create an account. Enter amounts using your local decimal separator, without thousands separators.")
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
                        TextField("Minimum balance (\(currencyCode))", text: $minimumText.groupedAmount())
                    }
                    Toggle("Balance above limit", isOn: $settings.notifyAboveMaximum)
                    if settings.notifyAboveMaximum {
                        TextField("Maximum balance (\(currencyCode))", text: $maximumText.groupedAmount())
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
            values.currentBalance = try AccountAmountInput.parse(balanceText)
            if values.notifyBelowMinimum { values.minimumBalance = try AccountAmountInput.parse(minimumText) }
            if values.notifyAboveMaximum { values.maximumBalance = try AccountAmountInput.parse(maximumText) }
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
