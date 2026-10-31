import SwiftUI
import WalletDomain

struct RecordDetailView: View {
    @ObservedObject var viewModel: RecordsViewModel
    let initialRecord: WalletRecord
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var mutationError: String?
    @State private var photo: Data?
    @State private var photoError: String?
    @Environment(\.currencyViewModel) private var currencyModel
    @Environment(\.receiptUseCases) private var receiptUseCases

    init(viewModel: RecordsViewModel, record: WalletRecord) {
        self.viewModel = viewModel
        initialRecord = record
    }

    private var record: WalletRecord {
        viewModel.records.first { $0.id == initialRecord.id } ?? initialRecord
    }

    private var draft: RecordDraft { record.draft }
    private var labels: [WalletTag] { viewModel.tags.filter { draft.tagIDs.contains($0.id) } }

    var body: some View {
        List {
            headerSection
            generalSection
            detailsSection
            if let receiptUseCases {
                ReceiptGallerySection(
                    viewModel: ReceiptsViewModel(useCases: receiptUseCases, recordID: record.id))
            }
            if record.hasPhoto || photo != nil || photoError != nil { photoSection }
        }
        .navigationTitle(draft.kind.title)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button("Edit") { editing = true }.disabled(viewModel.isSaving)
            }
            ToolbarItem {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    // A destructive role colours a row's title and nothing else, so the icon is
                    // said outright; the tint is what a toolbar button takes its colour from.
                    Label("Delete", systemImage: "trash").foregroundStyle(.red)
                }
                .tint(.red)
                .disabled(viewModel.isSaving)
            }
        }
        .sheet(isPresented: $editing, onDismiss: {
            // The editor can delete the record; there is then nothing left to show here.
            guard viewModel.records.contains(where: { $0.id == initialRecord.id }) else { dismiss(); return }
            Task { await loadPhoto() }
        }) {
            RecordEditorView(viewModel: viewModel, record: record)
        }
        .alert("Delete Record?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do { try await viewModel.delete(id: record.id); dismiss() }
                    catch { mutationError = error.localizedDescription }
                }
            }
        } message: { Text("This removes the record and its photo and reverses its effect on account balances.") }
        .alert("Unable to Change Record", isPresented: Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })) {
            Button("OK", role: .cancel) { mutationError = nil }
        } message: { Text(mutationError ?? "") }
        .task { await loadPhoto() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: WalletMetrics.medium) {
                if let category = viewModel.category(draft.categoryID) {
                    CategoryIcon(category: category).scaleEffect(1.25)
                } else {
                    WalletIconTile(symbol: draft.kind.symbol, color: draft.kind.tint, large: true)
                }
                WalletAmountText(amount: draft.amount, currencyCode: record.currencyCode, kind: draft.kind,
                                 font: .system(.largeTitle, design: .rounded, weight: .semibold))
                if let converted = convertedAmount, let home = currencyModel?.homeCurrency {
                    ConvertedAmountText(amount: converted, currencyCode: home, font: .footnote)
                }
                VStack(spacing: WalletMetrics.tight) {
                    Text(draft.kind == .transfer && draft.categoryID == nil
                         ? draft.kind.title
                         : viewModel.categoryName(draft.categoryID))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(draft.date.formatted(date: .complete, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WalletMetrics.large)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    /// This record's amount in the home currency, using its pinned rate when it has one.
    private var convertedAmount: Decimal? {
        guard let currencyModel, currencyModel.convertsTotals,
              record.currencyCode != currencyModel.homeCurrency else { return nil }
        return currencyModel.convert(draft.amount, from: record.currencyCode, manualRate: draft.manualRate)
    }

    /// For a cross-currency transfer, what the conversion gained or lost in the home currency.
    private var transferDifference: Decimal? {
        guard draft.kind == .transfer, let currencyModel, currencyModel.convertsTotals,
              let destination = record.destinationCurrencyCode else { return nil }
        return currencyModel.transferDifference(sent: draft.amount, sentCurrency: record.currencyCode,
                                                received: draft.receivedAmount ?? draft.amount,
                                                receivedCurrency: destination)
    }

    private var generalSection: some View {
        Section("Accounts") {
            LabeledContent(draft.kind == .transfer ? "From" : "Account",
                           value: viewModel.account(draft.accountID)?.name ?? "Archived / unlinked")
            if draft.kind == .transfer {
                LabeledContent("To", value: viewModel.account(draft.destinationAccountID)?.name ?? "Archived / unlinked")
                LabeledContent("Received") {
                    Text((draft.receivedAmount ?? draft.amount)
                        .walletFormatted(record.destinationCurrencyCode ?? record.currencyCode))
                        .monospacedDigit()
                }
                if let difference = transferDifference, let home = currencyModel?.homeCurrency {
                    LabeledContent(difference >= 0 ? "Currency gain" : "Currency loss") {
                        WalletAmountText.net(difference, currencyCode: home, font: .body.weight(.medium))
                    }
                }
            }
            if let rate = draft.manualRate, let home = currencyModel?.homeCurrency {
                LabeledContent("Pinned rate",
                               value: "1 \(record.currencyCode) = \(RecordAmountDisplay.grouped(rate)) \(home)")
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            if labels.isEmpty {
                LabeledContent("Labels", value: "None")
            } else {
                VStack(alignment: .leading, spacing: WalletMetrics.small) {
                    Text("Labels").font(.subheadline).foregroundStyle(.secondary)
                    WrappingLabels(tags: labels)
                }
                .padding(.vertical, WalletMetrics.hair)
            }
            LabeledContent("Payee", value: draft.payee.isEmpty ? "None" : draft.payee)
            LabeledContent("Payment type", value: draft.paymentType.title)
            VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                Text("Note").font(.subheadline).foregroundStyle(.secondary)
                Text(draft.note.isEmpty ? "No note" : draft.note)
                    .foregroundStyle(draft.note.isEmpty ? Color.secondary : Color.primary)
            }
            .padding(.vertical, WalletMetrics.hair)
        }
    }

    private var photoSection: some View {
        Section("Attachment") {
            if let photo {
                RecordPhotoView(data: photo)
            } else if let photoError {
                Label(photoError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else {
                ProgressView("Loading photo…")
            }
        }
    }

    private func loadPhoto() async {
        photo = nil
        photoError = nil
        guard record.hasPhoto else { return }
        do {
            photo = try await viewModel.photo(id: record.id)
            if photo == nil { photoError = "Photo unavailable." }
        } catch { photoError = error.localizedDescription }
    }
}

/// Labels shown as colored chips that wrap onto as many lines as they need.
private struct WrappingLabels: View {
    let tags: [WalletTag]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WalletMetrics.small) { chips }
            VStack(alignment: .leading, spacing: WalletMetrics.small) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(tags) { tag in
            HStack(spacing: WalletMetrics.tight) {
                Circle().fill(tag.color.tint).frame(width: 8, height: 8)
                Text(tag.name).font(.caption.weight(.medium))
            }
            .padding(.horizontal, WalletMetrics.small)
            .padding(.vertical, WalletMetrics.tight)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Label \(tag.name)")
        }
    }
}
