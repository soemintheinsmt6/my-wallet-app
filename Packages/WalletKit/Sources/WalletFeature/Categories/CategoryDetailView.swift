import SwiftUI
import WalletDomain

struct CategoryDetailView: View {
    @ObservedObject var viewModel: CategoriesViewModel
    let categoryID: UUID
    var planning: PlanningViewModel?
    @State private var editor: CategoryEditorRoute?
    @State private var deleting: WalletCategory?

    private var category: WalletCategory? { viewModel.category(id: categoryID) }

    var body: some View {
        Group {
            if let category {
                // Flat, with the editors' band headings, rather than grouped cards; still a list so
                // subcategories keep swipe to delete and the screen keeps pull to refresh.
                List {
                    header(category)
                    if let planning {
                        BudgetProgressSection(viewModel: planning, categoryID: category.id, bandHeader: true)
                    }
                    subcategories(category)
                    actions(category)
                }
                .listStyle(.plain)
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
        .refreshable { await viewModel.reload() }
    }

    private func header(_ category: WalletCategory) -> some View {
        Group {
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
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
        }
    }

    /// Rows under a band row rather than a section with a header, so the space under the last row
    /// matches the space above the first (see `WalletListSectionHeader`).
    @ViewBuilder private func subcategories(_ category: WalletCategory) -> some View {
        let children = viewModel.subcategories(of: category.id)
        WalletListSectionHeader("Subcategories")
        Group {
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
                        WalletDisclosure()
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
            // A row like the subcategories above it: a tile in the category's color, then the action.
            Button { editor = CategoryEditorRoute(parent: category) } label: {
                HStack(spacing: WalletMetrics.medium) {
                    WalletIconTile(symbol: "plus", color: category.colorToken.color)
                    Text("Create Subcategory").foregroundStyle(.tint)
                    Spacer()
                }
                .frame(minHeight: WalletMetrics.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The band below separates the groups, so the last row draws no rule of its own.
            .listRowSeparator(.hidden, edges: .bottom)
        }
    }

    /// Name, icon, color and nature are all in the editor, so editing is one row; the color and
    /// icon rows that repeated it here are gone.
    @ViewBuilder private func actions(_ category: WalletCategory) -> some View {
        WalletListSectionHeader("Manage")
        Button { editor = CategoryEditorRoute(category: category) } label: {
            Label("Edit Category", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        WalletDestructiveRow(title: "Delete Category") { deleting = category }
            .listRowSeparator(.hidden, edges: .bottom)
    }
}
