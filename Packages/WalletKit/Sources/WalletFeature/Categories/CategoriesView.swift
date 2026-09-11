import SwiftUI
import WalletDomain

public struct CategoriesView: View {
    @ObservedObject private var viewModel: CategoriesViewModel
    private let planning: PlanningViewModel?
    /// Supplied by the app so a record dropped on a category can be refiled through the record
    /// use cases; this screen has no record view model of its own.
    private let refile: ((Set<UUID>, UUID) async -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: CategoryEditorRoute?
    @State private var dropTarget: UUID?

    public init(viewModel: CategoriesViewModel, planning: PlanningViewModel? = nil,
                refile: ((Set<UUID>, UUID) async -> Void)? = nil) {
        self.viewModel = viewModel
        self.planning = planning
        self.refile = refile
    }

    public var body: some View {
        List(viewModel.rootCategories) { category in
            // A destination-based link, not `NavigationLink(value:)`: this screen is itself pushed
            // onto the More tab's stack, so a `navigationDestination` declared here registers a
            // push behind the stack and the detail lands one push late.
            NavigationLink {
                CategoryDetailView(viewModel: viewModel, categoryID: category.id, planning: planning)
            } label: {
                HStack(spacing: WalletMetrics.medium) {
                    CategoryIcon(category: category)
                    Text(category.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                .frame(minHeight: WalletMetrics.touchTarget)
                .padding(.vertical, WalletMetrics.hair)
            }
            .listRowBackground(dropTarget == category.id ? Color.accentColor.opacity(0.15) : nil)
            .dropDestination(for: RecordTransfer.self) { items, _ in
                guard let refile, !items.isEmpty else { return false }
                let ids = Set(items.map(\.recordID))
                Task { await refile(ids, category.id) }
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? category.id : (dropTarget == category.id ? nil : dropTarget)
            }
            .contextMenu {
                Button("Edit Category") { editor = CategoryEditorRoute(category: category) }
            }
        }
        .overlay {
            if viewModel.categories.isEmpty {
                if viewModel.isLoading {
                    WalletLoadingState(message: "Loading categories…")
                } else if viewModel.errorMessage == nil {
                    WalletEmptyState(title: "No categories", symbol: "folder",
                                     message: "Create a category to organize your records.",
                                     actionTitle: "Create Category") { editor = CategoryEditorRoute() }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem {
                Button { editor = CategoryEditorRoute() } label: {
                    Label("Create Category", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { CategoryEditorView(viewModel: viewModel, route: $0) }
        .refreshable { await viewModel.reload() }
        .alert("Unable to Load Categories", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") { Task { await viewModel.reload() } }
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }
}
