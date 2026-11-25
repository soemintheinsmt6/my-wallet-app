import SwiftUI
import WalletDomain

/// Adds more money lent or borrowed to an existing debt, kept as its own step in the debt's
/// history rather than written over its amount. Laid out like the settlement sheet.
struct DebtAdditionView: View {
    @ObservedObject var viewModel: DebtsViewModel
    let progress: DebtProgress
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var accountID: UUID?
    @State private var errorMessage: String?
    @State private var screen: Screen?
    @State private var didLoad = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case amount }
    private enum Screen: Hashable { case account, note }

    private var debt: Debt { progress.debt }
    private var lending: Bool { debt.direction == .owedToMe }
    private var currency: String { debt.currencyCode }

    /// Only accounts in the debt's own currency, so the adjustment cannot misstate the amount.
    private var accounts: [Account] {
        viewModel.records.accounts.filter { $0.currencyCode == currency }
    }

    /// The chosen account, else the one the debt's money first moved through, else the first.
    private var account: Account? {
        accounts.first { $0.id == accountID }
            ?? viewModel.openingAccount(of: debt).flatMap { opening in accounts.first { $0.id == opening.id } }
            ?? accounts.first
    }

    private var parsed: Decimal? {
        guard let value = try? AccountAmountInput.parse(amount), value > 0 else { return nil }
        return value
    }

    /// A debt whose money moved records every step of it, or settling would return money that was
    /// never taken out; one whose money did not records none.
    private var canSave: Bool { parsed != nil && !viewModel.isSaving && (!debt.movedMoney || account != nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    debtSection
                    detailsSection
                    if debt.movedMoney { moneySection }
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
            .navigationTitle(lending ? "Lend More" : "Borrow More")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $screen) { screen in
                switch screen {
                case .account:
                    RecordAccountSelection(accounts: accounts,
                                           selection: Binding(get: { account?.id }, set: { accountID = $0 }),
                                           title: "Account")
                case .note:
                    RecordTextEntry(title: "Note", text: $note, caption: "What was it for?", multiline: true)
                }
            }
            .disabled(viewModel.isSaving)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WalletEditorBottomButton(title: "Add to Debt", isBusy: viewModel.isSaving, isEnabled: canSave) {
                    add()
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

    /// Green for more owed to the user, red for more they owe, as the debt editor's amount is.
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lending ? "Lent to \(debt.person)" : "Borrowed from \(debt.person)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityHidden(true)
            RecordAmountField(sign: "+", color: lending ? .green : .red,
                              label: lending ? "Amount lent" : "Amount borrowed",
                              currency: currency, amount: $amount, focus: $focusedField, field: .amount)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Where the debt stands now and where it will stand after this.
    @ViewBuilder private var debtSection: some View {
        WalletEditorSectionHeader(title: "Debt") { focusedField = nil }
        RecordFormRow(symbol: progress.tileSymbol, color: progress.tileColor, filledIcon: true) {
            Text("Outstanding")
            Spacer()
            Text(progress.outstanding.walletFormatted(currency)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        RecordFormRow(symbol: "plus", color: lending ? .green : .orange, filledIcon: true, showsDivider: false) {
            Text("After this")
            Spacer()
            Text((progress.outstanding + (parsed ?? 0)).walletFormatted(currency))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        WalletEditorCaption("Kept as its own entry in the debt's history, so each time you "
                            + (lending ? "lend" : "borrow") + " stays on record.")
    }

    @ViewBuilder private var detailsSection: some View {
        WalletEditorSectionHeader(title: "Details") { focusedField = nil }
        RecordFormRow(symbol: "calendar") {
            RecordDateTimeField(date: $date) { focusedField = nil }
        }
        RecordFormRow(symbol: "square.and.pencil", showsDivider: false) {
            WalletEditorNavigationButton(title: "Note", value: note.isEmpty ? nil : note) { open(.note) }
        }
    }

    /// The debt's money was recorded moving when it was made, so this money is recorded the same way.
    @ViewBuilder private var moneySection: some View {
        WalletEditorSectionHeader(title: "Money") { focusedField = nil }
        if accounts.isEmpty {
            RecordFormRow(symbol: "exclamationmark.triangle.fill", color: .orange, filledIcon: true,
                          showsDivider: false) {
                Text("No account uses \(currency).").foregroundStyle(.orange)
                Spacer()
            }
            .frame(minHeight: 44)
        } else {
            RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true, showsDivider: false) {
                WalletEditorNavigationButton(title: lending ? "From account" : "Into account",
                                             value: account?.name) { open(.account) }
            }
        }
        WalletEditorCaption("Records \"" + (lending ? "Lent to" : "Borrowed from") + " \(debt.person)\" on this "
                            + "account, as the debt's money was recorded, so it is not counted as "
                            + (lending ? "spending." : "income."))
    }

    private func open(_ destination: Screen) {
        focusedField = nil
        screen = destination
    }

    private func add() {
        guard let value = parsed else { return }
        Task {
            do {
                try await viewModel.add(to: progress, amount: value, date: date, note: note,
                                        account: debt.movedMoney ? account : nil)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
