import SwiftUI
import WalletDomain

/// Records a payment against a debt, optionally writing a matching ledger record.
struct DebtSettlementView: View {
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
    /// Income and expenses need a category; an adjustment, for a debt whose money moved, has none.
    private var needsCategory: Bool { createsRecord && !progress.debt.movedMoney }
    private var canSave: Bool {
        parsed != nil && !viewModel.isSaving && (!createsRecord || account != nil) && (!needsCategory || categoryID != nil)
    }

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
                    RecordCategoryPicker(viewModel: viewModel.records, kind: kind, selection: $categoryID) {
                        self.screen = nil
                    }
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
                // A balance adjustment has no category, so a debt whose money moved asks for none.
                RecordFormRow(symbol: WalletSymbols.walletFill, color: .blue, filledIcon: true,
                              showsDivider: !progress.debt.movedMoney) {
                    WalletEditorNavigationButton(title: "Account", value: account?.name) { open(.account) }
                }
                if !progress.debt.movedMoney {
                    RecordFormRow(symbol: "questionmark", category: viewModel.records.category(categoryID),
                                  categoryTile: true, showsDivider: false) {
                        WalletEditorNavigationButton(title: "Category",
                                                     value: categoryID == nil ? "Choose" : viewModel.records.categoryName(categoryID)) {
                            open(.category)
                        }
                    }
                }
            }
        }
        WalletEditorCaption(ledgerCaption)
    }

    private var ledgerCaption: String {
        guard createsRecord else { return "The payment is tracked against the debt only; no balance changes." }
        if progress.debt.movedMoney {
            let person = progress.debt.person
            return "Records \"" + (kind == .income ? "Repaid by \(person)" : "Repaid to \(person)")
                + "\" on the chosen account, as the loan was recorded, so it is not counted as "
                + (kind == .income ? "income." : "spending.")
        }
        return "Creates \(kind == .income ? "an income" : "an expense") in the chosen account so balances "
            + "and statistics stay right."
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
