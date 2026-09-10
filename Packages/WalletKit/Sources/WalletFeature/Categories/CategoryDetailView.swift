import SwiftUI
import WalletDomain

struct CategoryDetailView: View {
    @ObservedObject var viewModel: CategoriesViewModel
    let categoryID: UUID
    var planning: PlanningViewModel? = nil
    @State private var editor: CategoryEditorRoute?
    @State private var deleting: WalletCategory?

    private var category: WalletCategory? { viewModel.category(id: categoryID) }

    var body: some View {
        Group {
            if let category {
                List {
                    Section {
                        HStack(spacing: 8) {
                            Text(category.name)
                                .font(.headline)
                                .lineLimit(1)
                            CategoryNatureBadge(nature: category.nature).fixedSize()
                        }
                        LabeledContent("Category color") {
                            Circle().fill(category.colorToken.color).frame(width: 20, height: 20)
                                .accessibilityLabel("Fixed category color \(category.colorToken.hex)")
                        }
                        Button("Edit Category") { editor = CategoryEditorRoute(category: category) }
                        Button("Delete Category", role: .destructive) { deleting = category }
                    }
                    if let planning { BudgetProgressSection(viewModel: planning, categoryID: category.id) }
                    Section("Subcategories") {
                        ForEach(viewModel.subcategories(of: category.id)) { child in
                            Button { editor = CategoryEditorRoute(category: child, parent: category) } label: {
                                HStack(spacing: 10) {
                                    CategoryIcon(category: child)
                                    Text(child.name).lineLimit(1)
                                    CategoryNatureBadge(nature: child.nature).fixedSize()
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                                .foregroundStyle(.primary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit subcategory")
                            .swipeActions { Button("Delete", role: .destructive) { deleting = child } }
                            .contextMenu { Button("Delete Subcategory", role: .destructive) { deleting = child } }
                        }
                        Button { editor = CategoryEditorRoute(parent: category) } label: {
                            Label("Create Subcategory", systemImage: "plus")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Category unavailable", systemImage: "folder.badge.questionmark", description: Text("Return to Categories and refresh."))
            }
        }
        .navigationTitle(category?.name ?? "Category")
        .sheet(item: $deleting) { CategoryDeletionView(viewModel: viewModel, category: $0) }
        .sheet(item: $editor) { CategoryEditorView(viewModel: viewModel, route: $0) }
        .refreshable { await viewModel.reload() }
    }
}
