import SwiftUI
import WalletDomain

public struct WalletView: View {
    @StateObject private var viewModel: WalletViewModel
    @Environment(\.scenePhase) private var scenePhase

    public init(viewModel: WalletViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.entries) { entry in
                    NavigationLink {
                        Text(entry.timestamp, format: .dateTime)
                            .navigationTitle("Entry")
                    } label: {
                        Text(entry.timestamp, format: .dateTime)
                    }
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { viewModel.entries[$0].id })
                    Task { await viewModel.delete(ids: ids) }
                }
                .deleteDisabled(viewModel.isSaving)
            }
            .overlay {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    ProgressView()
                } else if viewModel.entries.isEmpty {
                    ContentUnavailableView("No entries yet", systemImage: WalletSymbols.wallet, description: Text("Add an entry to get started."))
                }
            }
            .navigationTitle("My Wallet")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await viewModel.add() }
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .refreshable { await viewModel.reload() }
            .alert("Unable to Update Wallet", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }
}
