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
    @State private var adding: DebtProgress?
    @State private var editingRecord: WalletRecord?
    @State private var confirmingDelete = false
    @State private var mutationError: String?
    @State private var photo: Data?
    @State private var viewingPhoto = false
    /// Starts collapsed each time the screen opens.
    @State private var showsAllHistory = false
    @Environment(\.dismiss) private var dismiss

    private var progress: DebtProgress? { viewModel.debts.first { $0.debt.id == debtID } }

    var body: some View {
        Group {
            if let progress {
                List {
                    header(progress)
                    photoSection
                    history(progress)
                    records(progress)
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
        .sheet(item: $adding) { DebtAdditionView(viewModel: viewModel, progress: $0) }
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
        .sheet(isPresented: $viewingPhoto) {
            if let photo, let debt = progress?.debt {
                RecordPhotoViewer(data: photo) {
                    Task {
                        do { try await viewModel.removePhoto(from: debt) }
                        catch { mutationError = error.localizedDescription }
                    }
                }
            }
        }
        // Reloads when the debt changes, and when the editor closes: replacing one photo with another
        // leaves the debt itself unchanged.
        .task(id: photoVersion) { await loadPhoto() }
        .onChange(of: editing == nil) { _, closed in if closed { Task { await loadPhoto() } } }
        .refreshable { await viewModel.refresh() }
        .disabled(viewModel.isSaving)
    }

    /// Changes whenever the saved debt does, so an edit that replaced the photo reloads it.
    private var photoVersion: Debt? { progress?.debt }

    private func loadPhoto() async {
        guard let debt = progress?.debt, debt.hasPhoto else {
            photo = nil
            return
        }
        do {
            let data = try await viewModel.photo(id: debt.id)
            try Task.checkCancellation()
            photo = data
        } catch is CancellationError {
        } catch { mutationError = error.localizedDescription }
    }

    /// The attached photo, fitted to the screen's width; tapping it opens it full size, where it
    /// can be deleted.
    @ViewBuilder private var photoSection: some View {
        if let photo {
            WalletListSectionHeader("Photo")
            Button { viewingPhoto = true } label: {
                RecordPhotoView(data: photo, maxHeight: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show photo")
            .listRowSeparator(.hidden)
        }
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
                    WalletProgressBar(value: progress.fraction, tint: progress.tileColor, height: 8)
                    Text("\(progress.paid.walletFormatted(currency)) paid of \(progress.total.walletFormatted(currency))")
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
                WalletActionButton(title: "Settle", tint: progress.tileColor) { settling = progress }
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

    /// Every step of the debt, newest first: what it started at, each time more was lent or borrowed,
    /// and each payment, with the balance after it. Money added reads with a plus, payments with a
    /// minus. Additions and payments swipe away; the opening amount is changed by editing the debt.
    /// A record a step added is kept when the step is deleted, as deleting the debt keeps them.
    ///
    /// A long history opens collapsed to its latest few steps, so the records and actions below stay
    /// in reach; Show All on the header's trailing edge expands the rest in place, then Show Less.
    @ViewBuilder private func history(_ progress: DebtProgress) -> some View {
        let currency = progress.debt.currencyCode
        let all = Array(progress.history.reversed())
        let collapsible = all.count > Self.collapsedHistoryCount
        let rows = collapsible && !showsAllHistory ? Array(all.prefix(Self.collapsedHistoryCount)) : all
        WalletListSectionHeader("History") {
            if collapsible {
                Button(showsAllHistory ? "Show Less" : "Show All \(all.count)") {
                    withAnimation { showsAllHistory.toggle() }
                }
                .buttonStyle(.borderless)
                .accessibilityHint(showsAllHistory ? "Shows only the latest steps" : "Shows every step")
            }
        }
        ForEach(rows, id: \.entry.id) { row in
            historyRow(row, progress: progress, currency: currency)
                .listRowSeparator(row.entry.id == rows.last?.entry.id ? .hidden : .automatic, edges: .bottom)
                .swipeActions {
                    if case .opening = row.entry {} else {
                        Button("Delete", role: .destructive) { delete(row.entry) }
                    }
                }
        }
    }

    /// How many of the latest steps a collapsed history shows.
    private static let collapsedHistoryCount = 3

    private func historyRow(_ row: DebtHistoryStep, progress: DebtProgress, currency: String) -> some View {
        let lending = progress.debt.direction == .owedToMe
        let isPayment: Bool = { if case .payment = row.entry { true } else { false } }()
        let title: String
        var detail: String?
        switch row.entry {
        case .opening: title = lending ? "Lent" : "Borrowed"
        case .addition(let addition):
            title = lending ? "Lent more" : "Borrowed more"
            detail = addition.note.isEmpty ? nil : addition.note
        case .payment: title = lending ? "Repaid to you" : "You repaid"
        }
        let date = row.entry.date.formatted(date: .abbreviated, time: .omitted)
        return HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: isPayment ? "checkmark" : "plus",
                           color: isPayment ? .blue : lending ? .green : .orange)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(title)
                Text([date, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: WalletMetrics.small)
            VStack(alignment: .trailing, spacing: WalletMetrics.hair) {
                Text((isPayment ? "−" : "+") + row.entry.amount.walletFormatted(currency))
                    .monospacedDigit()
                    .foregroundStyle(isPayment ? Color.primary : lending ? Color.green : Color.red)
                Text("Owed \(row.balance.walletFormatted(currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .walletListRowPadding(WalletMetrics.tight)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.entry.recordID == nil ? "Tracked against the debt only" : "Added a record")
    }

    private func delete(_ entry: DebtEntry) {
        Task {
            do {
                switch entry {
                case .opening: return
                case .addition(let addition): try await viewModel.deleteAddition(id: addition.id)
                case .payment(let payment): try await viewModel.deletePayment(id: payment.id)
                }
            } catch { mutationError = error.localizedDescription }
        }
    }

    @ViewBuilder private func actions(_ progress: DebtProgress) -> some View {
        WalletListSectionHeader("Manage")
        Button { adding = progress } label: {
            Label(progress.debt.direction == .owedToMe ? "Lend More" : "Borrow More", systemImage: "plus.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
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
