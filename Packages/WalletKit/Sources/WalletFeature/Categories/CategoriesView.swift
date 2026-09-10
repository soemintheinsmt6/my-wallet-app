import SwiftUI
import WalletDomain

public struct CategoriesView: View {
    @ObservedObject private var viewModel: CategoriesViewModel
    private let planning: PlanningViewModel?
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: CategoryEditorRoute?

    public init(viewModel: CategoriesViewModel, planning: PlanningViewModel? = nil) { self.viewModel = viewModel; self.planning = planning }

    public var body: some View {
        NavigationStack {
            List(viewModel.rootCategories) { category in
                NavigationLink(value: category.id) {
                    HStack(spacing: 14) {
                        CategoryIcon(category: category)
                        Text(category.name)
                            .font(.headline)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 44)
                }
                .contextMenu {
                    Button("Edit Category") { editor = CategoryEditorRoute(category: category) }
                }
            }
            .overlay {
                if viewModel.categories.isEmpty {
                    if viewModel.isLoading {
                        ProgressView("Loading categories…")
                    } else if viewModel.errorMessage == nil {
                        ContentUnavailableView("No categories", systemImage: "folder", description: Text("Create a category to organize your records."))
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationDestination(for: UUID.self) { id in
                CategoryDetailView(viewModel: viewModel, categoryID: id, planning: planning)
            }
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
        }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }
}
