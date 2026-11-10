import SwiftUI
import WalletDomain

/// One debt at a glance, with settling as its main action, as a bill's screen leads with Mark as
/// Paid. A flat list with the editors' bands, like the bill and category screens, so payments keep
/// swipe to delete and the screen keeps pull to refresh.
struct DebtDetailView: View {
    @ObservedObject var viewModel: DebtsViewModel
    let debtID: UUID
    @State private var editing: Debt?
    @State private var settling: DebtProgress?
    @State private var editingRecord: WalletRecord?
    @State private var confirmingDelete = false
    @State private var mutationError: String?
    @Environment(\.dismiss) private var dismiss

    private var progress: DebtProgress? { viewModel.debts.first { $0.debt.id == debtID } }

    var body: some View {
        Group {
            if let progress {
                List {
                    header(progress)
                    records(progress)
                    payments(progress)
                    actions(progress)
                }
                .listStyle(.plain)
            } else {
                WalletEmptyState(title: "Debt unavailable", symbol: "person.2.slash",
                                 message: "It may have been deleted on another device.")
            }
        }
        .navigationTitle(progress?.debt.person ?? "Debt")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { DebtEditorView(viewModel: viewModel, debt: $0) }
        .sheet(item: $settling) { DebtSettlementView(viewModel: viewModel, progress: $0) }
        .sheet(item: $editingRecord) { RecordEditorView(viewModel: viewModel.records, record: $0) }
        // Deleted from here or from its editor: there is nothing left to show.
        .onChange(of: progress == nil) { _, isGone in if isGone { dismiss() } }
        .alert("Delete Debt?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do { try await viewModel.deleteDebt(id: debtID) }
                    catch { mutationError = error.localizedDescription }
                }
            }
        } message: { Text("Its payment history is removed too. Any records created when settling are kept.") }
        .alert("Unable to Change Debt", isPresented: Binding(get: { mutationError != nil },
                                                             set: { if !$0 { mutationError = nil } })) {
            Button("OK", role: .cancel) { mutationError = nil }
        } message: { Text(mutationError ?? "") }
        .refreshable { await viewModel.refresh() }
        .disabled(viewModel.isSaving)
    }

    /// The debt's tile, who owes whom, what is still outstanding and where it stands, then Settle.
    private func header(_ progress: DebtProgress) -> some View {
        let currency = progress.debt.currencyCode
        return VStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: progress.tileSymbol, color: progress.tileColor, large: true)
            VStack(spacing: WalletMetrics.small) {
                Text(progress.debt.direction.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(progress.outstanding.walletFormatted(currency))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(progress.isSettled ? Color.secondary : Color.primary)
                Text(progress.statusText)
                    .font(.subheadline)
                    .foregroundStyle(progress.isOverdue ? Color.red : Color.secondary)
            }
            if progress.paid > 0, !progress.isSettled {
                VStack(spacing: WalletMetrics.tight) {
                    ProgressView(value: progress.fraction)
                        .tint(progress.tileColor)
                        .accessibilityHidden(true)
                    Text("\(progress.paid.walletFormatted(currency)) paid of \(progress.debt.amount.walletFormatted(currency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if !progress.debt.note.isEmpty {
                Text(progress.debt.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !progress.isSettled {
                Button { settling = progress } label: {
                    Label("Settle", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(progress.tileColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WalletMetrics.large)
        .listRowSeparator(.hidden)
    }

    /// The same rows as the Records list, so the debt's money reads as it does there; each opens
    /// its record.
    @ViewBuilder private func records(_ progress: DebtProgress) -> some View {
        let records = viewModel.records(for: progress)
        if !records.isEmpty {
            WalletListSectionHeader("Records")
            ForEach(records) { record in
                Button { editingRecord = record } label: {
                    RecordRow(viewModel: viewModel.records, record: record, showsDate: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit record")
                .listRowSeparator(record.id == records.last?.id ? .hidden : .automatic, edges: .bottom)
            }
        }
    }

    /// Each payment, newest first, saying whether it added a record. Swiping one away reopens that
    /// much of the debt; a record it added is kept, as deleting the debt keeps them.
    @ViewBuilder private func payments(_ progress: DebtProgress) -> some View {
        if !progress.payments.isEmpty {
            let payments = Array(progress.payments.reversed())
            WalletListSectionHeader("Payments")
            ForEach(payments) { payment in
                WalletListValueRow(title: payment.date.formatted(date: .abbreviated, time: .omitted),
                                   value: payment.amount.walletFormatted(progress.debt.currencyCode)) {
                    WalletIconTile(symbol: payment.recordID == nil ? "checkmark" : "doc.text.fill",
                                   color: payment.recordID == nil ? .gray : .blue)
                }
                .accessibilityHint(payment.recordID == nil ? "Tracked against the debt only" : "Added a record")
                .listRowSeparator(payment.id == payments.last?.id ? .hidden : .automatic, edges: .bottom)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task {
                            do { try await viewModel.deletePayment(id: payment.id) }
                            catch { mutationError = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func actions(_ progress: DebtProgress) -> some View {
        WalletListSectionHeader("Manage")
        Button { editing = progress.debt } label: {
            Label("Edit Debt", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        WalletDestructiveRow(title: "Delete Debt") { confirmingDelete = true }
            .listRowSeparator(.hidden, edges: .bottom)
    }
}

/// How a debt is drawn wherever it appears, so the list and its screen agree.
extension DebtProgress {
    /// A check once settled; otherwise money coming in for a debt owed to the user, going out for one
    /// they owe.
    var tileSymbol: String {
        isSettled ? "checkmark.circle" : debt.direction == .owedToMe ? "arrow.down.left" : "arrow.up.right"
    }

    /// Gray once settled, red while overdue, otherwise green for money owed to the user and orange
    /// for money they owe.
    var tileColor: Color {
        isSettled ? .gray : isOverdue ? .red : debt.direction == .owedToMe ? .green : .orange
    }

    /// Settled, overdue or due on a date, or how much is paid when there is no due date.
    var statusText: String {
        if isSettled { return "Settled" }
        guard let due = debt.dueDate else {
            return paid > 0 ? "\(paid.walletFormatted(debt.currencyCode)) paid" : "No due date"
        }
        let when = due.formatted(date: .abbreviated, time: .omitted)
        return isOverdue ? "Overdue · \(when)" : "Due \(when)"
    }
}
