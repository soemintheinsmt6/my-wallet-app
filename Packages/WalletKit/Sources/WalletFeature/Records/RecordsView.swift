import SwiftUI
import WalletDomain

public struct RecordsView: View {
    @ObservedObject private var viewModel: RecordsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var creating = false
    @State private var pendingDelete: WalletRecord?
    @State private var deletionError: String?

    public init(viewModel: RecordsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        NavigationStack {
            List(viewModel.records) { record in
                NavigationLink {
                    RecordDetailView(viewModel: viewModel, record: record)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: record.draft.kind.symbol).foregroundStyle(record.draft.kind.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.draft.kind == .transfer && record.draft.categoryID == nil ? record.draft.kind.title : viewModel.categoryTitle(record.draft.categoryID)).font(.headline)
                            Text(viewModel.account(record.draft.accountID)?.name ?? "Archived / unlinked account").font(.caption).foregroundStyle(.secondary)
                            Text(record.draft.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(record.draft.amount, format: .currency(code: record.currencyCode).precision(.fractionLength(0...8)))
                                .monospacedDigit()
                            Text(record.draft.kind.title).font(.caption).foregroundStyle(record.draft.kind.tint)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = record }
                }
                .contextMenu {
                    Button("Delete Record", role: .destructive) { pendingDelete = record }
                }
                .disabled(viewModel.isSaving)
            }
            .alert("Delete Record?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    guard let record = pendingDelete else { return }
                    pendingDelete = nil
                    Task {
                        do { try await viewModel.delete(id: record.id) }
                        catch { deletionError = error.localizedDescription }
                    }
                }
            } message: { Text("This removes the record and its photo and reverses its effect on account balances.") }
            .alert("Unable to Delete Record", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: { Text(deletionError ?? "") }
            .overlay {
                if viewModel.records.isEmpty {
                    if viewModel.isLoading { ProgressView("Loading records…") }
                    else {
                        ContentUnavailableView {
                            Label("No records yet", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(viewModel.accounts.isEmpty ? "Create an account in the Accounts tab first." : "Add an expense, income, or transfer.")
                        } actions: {
                            if !viewModel.accounts.isEmpty { Button("Add Record") { creating = true }.buttonStyle(.borderedProminent) }
                        }
                    }
                }
            }
            .navigationTitle("Records")
            .toolbar {
                ToolbarItem {
                    Button { creating = true } label: { Label("Add Record", systemImage: "plus") }
                        .disabled(viewModel.accounts.isEmpty || viewModel.isLoading)
                }
            }
            .sheet(isPresented: $creating) { RecordEditorView(viewModel: viewModel) }
            .refreshable { await viewModel.reload() }
            .alert("Unable to Load Records", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("Retry") { Task { await viewModel.reload() } }
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await viewModel.reload() } } }
    }
}
