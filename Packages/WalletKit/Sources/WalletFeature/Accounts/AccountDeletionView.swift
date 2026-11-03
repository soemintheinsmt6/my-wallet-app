import SwiftUI
import WalletDomain

struct AccountDeletionView: View {
    @ObservedObject var viewModel: AccountsViewModel
    let account: Account
    /// Called once the account is gone, before this sheet closes, so a presenter can close too.
    var onDeleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var impact: AccountDeletionImpact?
    @State private var strategy = AccountDeletionStrategy.keepRecords
    @State private var confirming = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let impact {
                    Section("Deletion impact") {
                        LabeledContent("Account", value: impact.account.name)
                        LabeledContent("Balance", value: impact.account.settings.currentBalance.formatted(.currency(code: impact.account.currencyCode)))
                        LabeledContent("Associated records", value: "\(impact.recordCount)")
                        LabeledContent("Transfers", value: "\(impact.transferCount)")
                    }
                    Section {
                        WalletMenuPicker("Records", selection: $strategy,
                                         value: strategy == .keepRecords ? "Keep as unlinked records" : "Delete associated records") {
                            Text("Keep as unlinked records").tag(AccountDeletionStrategy.keepRecords)
                            Text("Delete associated records").tag(AccountDeletionStrategy.deleteRecords)
                        }
                        Text(strategy == .keepRecords
                             ? "Records and photos are retained. Links to this account are removed. Transfers keep their effect on the other account."
                             : "Associated records and photos are deleted. Transfers are removed from both sides, reversing their effect on the other account.")
                            .foregroundStyle(.secondary)
                        Button("Delete Account", role: .destructive) { confirming = true }
                    }
                } else if errorMessage == nil { ProgressView("Loading deletion impact…") }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                    if impact == nil { Button("Retry") { Task { await loadImpact() } } }
                }
            }
            .formStyle(.grouped)
            .disabled(viewModel.isSaving)
            .navigationTitle("Delete Account")
            .toolbar { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
            .alert("Delete \(account.name)?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await viewModel.delete(id: account.id, strategy: strategy)
                            onDeleted()
                            dismiss()
                        }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            } message: { Text("This cannot be undone. The selected strategy applies to all associated records, including transfers.") }
            .interactiveDismissDisabled(viewModel.isSaving)
            .task { await loadImpact() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private func loadImpact() async {
        errorMessage = nil
        do { impact = try await viewModel.deletionImpact(id: account.id) }
        catch { errorMessage = error.localizedDescription }
    }
}
