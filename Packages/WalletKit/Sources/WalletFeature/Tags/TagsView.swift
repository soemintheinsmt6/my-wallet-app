import SwiftUI
import WalletDomain

public struct TagsView: View {
    @ObservedObject private var viewModel: TagsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var creating = false
    @State private var editing: WalletTag?
    @State private var deleting: WalletTag?

    public init(viewModel: TagsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List(viewModel.tags) { tag in
            Button { editing = tag } label: {
                HStack(spacing: WalletMetrics.medium) {
                    WalletIconTile(symbol: "tag.fill", color: tag.color.tint)
                    Text(tag.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: WalletMetrics.small)
                    WalletDisclosure()
                }
                .frame(minHeight: WalletMetrics.touchTarget)
                .padding(.vertical, WalletMetrics.hair)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit label")
            .swipeActions(allowsFullSwipe: false) {
                Button("Delete", role: .destructive) { deleting = tag }
            }
            .contextMenu {
                Button("Edit") { editing = tag }
                Button("Delete", role: .destructive) { deleting = tag }
            }
            .disabled(viewModel.isSaving)
            .walletFirstRow(tag.id == viewModel.tags.first?.id)
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.tags.isEmpty {
                if viewModel.isLoading {
                    WalletLoadingState(message: "Loading labels…")
                } else {
                    WalletEmptyState(title: "No labels yet", symbol: "tag",
                                     message: "Create labels such as Work or Vacation to organize your records.",
                                     actionTitle: "Create Label") { creating = true }
                }
            }
        }
        .navigationTitle("Labels")
        .toolbar {
            ToolbarItem {
                Button { creating = true } label: { Label("Create Label", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $creating) { TagEditorView(viewModel: viewModel) }
        .sheet(item: $editing) { TagEditorView(viewModel: viewModel, tag: $0) }
        .confirmationDialog("Delete Label?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            if let tag = deleting {
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await viewModel.delete(id: tag.id) }
                        catch { viewModel.errorMessage = error.localizedDescription }
                    }
                }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Delete \"\(deleting?.name ?? "")\"? This cannot be undone.") }
        .alert("Unable to Update Labels", isPresented: Binding(
            get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") { Task { await viewModel.reload() } }
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }
}
