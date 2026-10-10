import SwiftUI
import WalletDomain

/// Most used categories as a horizontal strip, then top-level categories only. A category with
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
                Section("Categories") {
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
        // Outside the list, so the strip runs edge to edge; list rows and headers keep side margins.
        .safeAreaInset(edge: .top, spacing: 0) {
            let frequent = viewModel.mostUsedCategories(for: kind)
            if search.isEmpty, !frequent.isEmpty { mostUsed(frequent) }
        }
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

    private func mostUsed(_ categories: [WalletCategory]) -> some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            Text("Most used")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, WalletMetrics.large)
            // No side padding: the tiles' own width centres each icon clear of the screen edge.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(categories) { category in
                        Button { pick(category.id) } label: {
                            VStack(spacing: WalletMetrics.small) {
                                CategoryIcon(category: category)
                                Text(category.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 80)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(category.name)
                    }
                }
            }
        }
        .padding(.vertical, WalletMetrics.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.screenBackground)
    }

    /// Matches the grouped list behind it, so the strip has no card of its own.
    private static var screenBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

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
        .navigationTitle(category.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
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
