import SwiftUI
import WalletDomain

struct RecordDetailView: View {
    @ObservedObject var viewModel: RecordsViewModel
    let record: WalletRecord
    @State private var photo: Data?
    @State private var photoError: String?

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Type", value: record.draft.kind.title)
                LabeledContent("Amount", value: record.draft.amount.formatted(.currency(code: record.currencyCode).precision(.fractionLength(0...8))))
                LabeledContent(record.draft.kind == .transfer ? "From account" : "Account", value: viewModel.account(record.draft.accountID)?.name ?? "Unavailable")
                if record.draft.kind == .transfer {
                    LabeledContent("To account", value: viewModel.account(record.draft.destinationAccountID)?.name ?? "Unavailable")
                    LabeledContent("Received", value: (record.draft.receivedAmount ?? record.draft.amount).formatted(.currency(code: record.destinationCurrencyCode ?? record.currencyCode).precision(.fractionLength(0...8))))
                }
                LabeledContent("Category", value: record.draft.categoryID == nil ? "None" : viewModel.categoryTitle(record.draft.categoryID))
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
        .task {
            guard record.hasPhoto else { return }
            do {
                photo = try await viewModel.photo(id: record.id)
                if photo == nil { photoError = "Photo unavailable." }
            }
            catch { photoError = error.localizedDescription }
        }
    }
}
