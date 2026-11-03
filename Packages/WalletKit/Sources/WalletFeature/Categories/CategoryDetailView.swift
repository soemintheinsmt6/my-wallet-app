import SwiftUI
import WalletDomain

struct CategoryDetailView: View {
    @ObservedObject var viewModel: CategoriesViewModel
    let categoryID: UUID
    var planning: PlanningViewModel? = nil
    @State private var editor: CategoryEditorRoute?
    @State private var deleting: WalletCategory?
    @State private var choosingSymbol = false
    @Environment(\.categorySymbolStore) private var symbols

    private var category: WalletCategory? { viewModel.category(id: categoryID) }

    var body: some View {
        Group {
            if let category {
                List {
                    header(category)
                    if let planning { BudgetProgressSection(viewModel: planning, categoryID: category.id) }
                    subcategories(category)
                    appearance(category)
                    actions(category)
                }
            } else {
                WalletEmptyState(title: "Category unavailable", symbol: "folder.badge.questionmark",
                                 message: "Return to Categories and refresh.")
            }
        }
        .navigationTitle(category?.name ?? "Category")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $deleting) { CategoryDeletionView(viewModel: viewModel, category: $0) }
        .sheet(item: $editor) { CategoryEditorView(viewModel: viewModel, route: $0) }
        .sheet(isPresented: $choosingSymbol) {
            if let category, let symbols {
                CategorySymbolPicker(category: category, overrides: symbols)
            }
        }
        .refreshable { await viewModel.reload() }
    }

    private func header(_ category: WalletCategory) -> some View {
        Section {
            VStack(spacing: WalletMetrics.medium) {
                CategoryIcon(category: category).scaleEffect(1.25)
                VStack(spacing: WalletMetrics.small) {
                    Text(category.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    CategoryNatureBadge(nature: category.nature).fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WalletMetrics.large)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    private func subcategories(_ category: WalletCategory) -> some View {
        let children = viewModel.subcategories(of: category.id)
        return Section {
            if children.isEmpty {
                Text("No subcategories yet.").foregroundStyle(.secondary)
            }
            ForEach(children) { child in
                Button { editor = CategoryEditorRoute(category: child, parent: category) } label: {
                    HStack(spacing: WalletMetrics.medium) {
                        CategoryIcon(category: child)
                        Text(child.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        CategoryNatureBadge(nature: child.nature).fixedSize()
                        Spacer(minLength: WalletMetrics.small)
                    }
                    .frame(minHeight: WalletMetrics.touchTarget)
                    .padding(.vertical, WalletMetrics.hair)
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
        } header: {
            Text("Subcategories")
        }
    }

    /// The colour is something the category has, not something to tap, so it is kept out of the
    /// rows that act.
    private func appearance(_ category: WalletCategory) -> some View {
        Section {
            LabeledContent("Color") {
                Circle()
                    .fill(category.colorToken.color)
                    .frame(width: 20, height: 20)
                    .accessibilityLabel("Fixed category color \(category.colorToken.hex)")
            }
        } footer: {
            Text("The category color is fixed and stays the same across renames and devices.")
        }
    }

    private func actions(_ category: WalletCategory) -> some View {
        Section {
            Button { editor = CategoryEditorRoute(category: category) } label: {
                Label("Edit Category", systemImage: "square.and.pencil")
            }
            if symbols != nil {
                Button { choosingSymbol = true } label: {
                    Label("Change Icon", systemImage: "square.grid.2x2")
                }
            }
            WalletDestructiveRow(title: "Delete Category") { deleting = category }
        }
    }
}
