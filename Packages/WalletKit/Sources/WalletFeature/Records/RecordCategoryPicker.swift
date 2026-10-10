import SwiftUI
import WalletDomain

/// Most used categories as a paged strip, then top-level categories only. A category with
/// subcategories opens its own list, where either it or one of its subcategories can be chosen.
struct RecordCategoryPicker: View {
    @ObservedObject var viewModel: RecordsViewModel
    let kind: RecordKind
    @Binding var selection: UUID?
    /// Offers clearing the selection; transfers always may.
    var allowsNone = false
    /// Called after a choice. The presenter closes the picker by clearing the state that pushed it,
    /// which also removes a subcategory list pushed above it. `dismiss` is avoided here because
    /// inside an editor sheet it can close the whole sheet.
    let onPicked: () -> Void
    @State private var search = ""
    /// The top-level category whose subcategory list is showing.
    @State private var expanded: UUID?

    private var roots: [WalletCategory] { viewModel.categories.filter { $0.parentID == nil } }
    private func children(of category: WalletCategory) -> [WalletCategory] {
        viewModel.categories.filter { $0.parentID == category.id }
    }

    var body: some View {
        List {
            if search.isEmpty {
                if kind == .transfer || allowsNone {
                    Button("No category") { pick(nil) }
                }
                let frequent = viewModel.mostUsedCategories(for: kind, limit: Self.pageSize * 2)
                if !frequent.isEmpty {
                    Section("Most frequent") {
                        MostUsedPager(categories: frequent, pageSize: Self.pageSize) { pick($0) }
                            .listRowInsets(EdgeInsets())
                    }
                }
                Section("All categories") {
                    ForEach(roots) { root in rootRow(root) }
                }
            } else {
                Section {
                    ForEach(viewModel.categories.filter { $0.name.localizedCaseInsensitiveContains(search) }) { category in
                        CategoryPickerRow(category: category, subtitle: viewModel.category(category.parentID)?.name) {
                            pick(category.id)
                        }
                    }
                }
            }
        }
        .categoryPickerListStyle()
        .searchable(text: $search, prompt: "Category or subcategory")
        .navigationTitle("Category")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $expanded) { id in
            if let root = viewModel.category(id) {
                SubcategoryPicker(category: root, subcategories: children(of: root), pick: pick)
            }
        }
    }

    /// Choosing anywhere, including from the subcategory list, returns straight to the form.
    private func pick(_ id: UUID?) {
        selection = id
        onPicked()
    }

    /// Five tiles fill a phone's width; the strip pages through at most two screens of them.
    private static let pageSize = 5

    @ViewBuilder
    private func rootRow(_ root: WalletCategory) -> some View {
        let subcategories = children(of: root)
        if subcategories.isEmpty {
            CategoryPickerRow(category: root) { pick(root.id) }
        } else {
            Button { expanded = root.id } label: {
                HStack {
                    CategoryIcon(category: root)
                    Text(root.name).foregroundStyle(.primary)
                    Spacer()
                    WalletDisclosure()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A category and its subcategories in separate sections; either can be the record's category.
private struct SubcategoryPicker: View {
    let category: WalletCategory
    let subcategories: [WalletCategory]
    let pick: (UUID?) -> Void

    var body: some View {
        List {
            Section("Category") {
                CategoryPickerRow(category: category) { pick(category.id) }
            }
            Section("Subcategories") {
                ForEach(subcategories) { child in
                    CategoryPickerRow(category: child) { pick(child.id) }
                }
            }
        }
        .categoryPickerListStyle()
        .navigationTitle(category.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Most used categories a page at a time, swiped sideways, with dots for the current page.
/// It scrolls horizontally only; a vertical drag passes through to the list around it.
private struct MostUsedPager: View {
    let categories: [WalletCategory]
    let pageSize: Int
    let pick: (UUID) -> Void
    @State private var page: Int? = 0

    private var pages: [[WalletCategory]] {
        stride(from: 0, to: categories.count, by: pageSize).map {
            Array(categories[$0 ..< min($0 + pageSize, categories.count)])
        }
    }

    var body: some View {
        VStack(spacing: WalletMetrics.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        HStack(spacing: 0) {
                            ForEach(pages[index]) { tile($0) }
                            // A short last page keeps its tiles at the same width and position.
                            ForEach(0 ..< pageSize - pages[index].count, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)

            if pages.count > 1 {
                HStack(spacing: WalletMetrics.small) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(index == (page ?? 0) ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        // The dots add weight below the tiles, so the top gets more room to balance them.
        .padding(.top, WalletMetrics.xLarge)
        .padding(.bottom, WalletMetrics.medium)
    }

    private func tile(_ category: WalletCategory) -> some View {
        Button { pick(category.id) } label: {
            VStack(spacing: WalletMetrics.small) {
                CategoryIcon(category: category)
                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, WalletMetrics.tight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.name)
    }
}

private extension View {
    /// Full-width rows under plain section headings, rather than inset cards.
    @ViewBuilder func categoryPickerListStyle() -> some View {
        #if os(iOS)
        listStyle(.grouped)
        #else
        self
        #endif
    }
}

private struct CategoryPickerRow: View {
    let category: WalletCategory
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                CategoryIcon(category: category)
                VStack(alignment: .leading) {
                    Text(category.name).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
