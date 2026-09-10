import SwiftUI
import WalletDomain

/// Captures an expense on the wrist and hands it to the phone.
///
/// Deliberately narrow: amount, one of the most-used categories, and the account. Anything richer
/// belongs on the phone, and the watch cannot validate against the real ledger anyway.
struct WatchQuickAddView: View {
    @ObservedObject var store: WatchWalletStore
    @State private var amountText = ""
    @State private var categoryID: UUID?
    @State private var accountID: UUID?
    @State private var confirmation: String?

    private var accounts: [WalletSnapshot.Option] { store.snapshot?.accounts ?? [] }
    private var categories: [WalletSnapshot.Option] { store.snapshot?.quickCategories ?? [] }

    private var account: WalletSnapshot.Option? {
        accounts.first { $0.id == accountID } ?? accounts.first
    }

    private var amount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if accounts.isEmpty {
                    WatchEmptyState(message: "Add an account on your iPhone first.")
                } else {
                    amountField
                    if accounts.count > 1 { accountPicker }
                    categoryPicker
                    addButton
                    status
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Add")
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(account?.currencyCode ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // The watch keyboard/dictation field is the only practical numeric entry here.
            TextField("0", text: $amountText)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Amount")
        }
    }

    private var accountPicker: some View {
        Picker("Account", selection: Binding(get: { account?.id }, set: { accountID = $0 })) {
            ForEach(accounts) { option in
                Text(option.title).tag(Optional(option.id))
            }
        }
        .pickerStyle(.navigationLink)
    }

    @ViewBuilder private var categoryPicker: some View {
        if categories.isEmpty {
            Text("Categories appear once you have recorded a few expenses.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Picker("Category", selection: $categoryID) {
                Text("None").tag(nil as UUID?)
                ForEach(categories) { option in
                    Label(option.title, systemImage: option.symbol).tag(Optional(option.id))
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var addButton: some View {
        Button {
            guard let amount, let account else { return }
            store.add(amount: amount, accountID: account.id, categoryID: categoryID)
            confirmation = store.isReachable ? "Sent to iPhone" : "Queued for iPhone"
            amountText = ""
        } label: {
            Text("Add Expense").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(amount == nil || account == nil)
    }

    @ViewBuilder private var status: some View {
        if let error = store.lastError {
            Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
        } else if let confirmation {
            Text(confirmation).font(.caption2).foregroundStyle(.green)
        }
        if store.pendingCount > 0 {
            Text("\(store.pendingCount) waiting to send")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
