import SwiftUI
import WalletDomain

struct RecordDetailView: View {
    @ObservedObject var viewModel: RecordsViewModel
    let initialRecord: WalletRecord
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var mutationError: String?

    init(viewModel: RecordsViewModel, record: WalletRecord) {
        self.viewModel = viewModel
        initialRecord = record
    }

    private var record: WalletRecord {
        viewModel.records.first { $0.id == initialRecord.id } ?? initialRecord
    }
    @State private var photo: Data?
    @State private var photoError: String?

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Type", value: record.draft.kind.title)
                LabeledContent("Amount", value: record.draft.amount.formatted(.currency(code: record.currencyCode).precision(.fractionLength(0...8))))
                LabeledContent(record.draft.kind == .transfer ? "From account" : "Account", value: viewModel.account(record.draft.accountID)?.name ?? "Archived / unlinked")
                if record.draft.kind == .transfer {
                    LabeledContent("To account", value: viewModel.account(record.draft.destinationAccountID)?.name ?? "Archived / unlinked")
                    LabeledContent("Received", value: (record.draft.receivedAmount ?? record.draft.amount).formatted(.currency(code: record.destinationCurrencyCode ?? record.currencyCode).precision(.fractionLength(0...8))))
                }
                LabeledContent("Category", value: viewModel.categoryTitle(record.draft.categoryID))
                LabeledContent("Date and time", value: record.draft.date.formatted(date: .abbreviated, time: .shortened))
                let labels = viewModel.tags.filter { record.draft.tagIDs.contains($0.id) }
                LabeledContent("Labels", value: labels.isEmpty ? "None" : labels.map(\.name).joined(separator: ", "))
            }
            Section("More Details") {
                LabeledContent("Payee", value: record.draft.payee.isEmpty ? "None" : record.draft.payee)
                LabeledContent("Payment type", value: record.draft.paymentType.title)
                Text(record.draft.note.isEmpty ? "No note" : record.draft.note)
                if let photo { RecordPhotoView(data: photo) }
                else if let photoError { Text(photoError).foregroundStyle(.red) }
                else if record.hasPhoto { ProgressView("Loading photo…") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(record.draft.kind.title)
        .toolbar {
            Button("Edit") { editing = true }.disabled(viewModel.isSaving)
            Button("Delete", role: .destructive) { confirmingDelete = true }.disabled(viewModel.isSaving)
        }
        .sheet(isPresented: $editing, onDismiss: { Task { await loadPhoto() } }) {
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
