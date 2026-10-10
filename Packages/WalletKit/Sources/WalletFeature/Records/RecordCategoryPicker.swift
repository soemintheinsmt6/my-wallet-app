import SwiftUI
import WalletDomain

struct RecordCategoryPicker: View {
    @ObservedObject var viewModel: RecordsViewModel
    let kind: RecordKind
    @Binding var selection: UUID?
    /// Offers clearing the selection; transfers always may.
    var allowsNone = false
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            if kind == .transfer || allowsNone {
                Button("No category") { selection = nil; dismiss() }
            }
            if search.isEmpty, !viewModel.mostUsedCategories(for: kind).isEmpty {
                Section("Most used") {
                    ForEach(viewModel.mostUsedCategories(for: kind)) { category in row(category, fullName: true) }
                }
            }
            ForEach(viewModel.categories.filter { $0.parentID == nil }) { root in
                let children = viewModel.categories.filter { $0.parentID == root.id }
                let matchesRoot = search.isEmpty || root.name.localizedCaseInsensitiveContains(search)
                let matches = matchesRoot ? children : children.filter { $0.name.localizedCaseInsensitiveContains(search) }
                if matchesRoot || !matches.isEmpty {
                    Section(root.name) {
                        if matchesRoot { row(root) }
                        ForEach(matches) { child in row(child).padding(.leading, 12) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Category or subcategory")
        .navigationTitle("Category")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(_ category: WalletCategory, fullName: Bool = false) -> some View {
        Button { selection = category.id; dismiss() } label: {
            HStack {
                CategoryIcon(category: category)
                Text(fullName ? viewModel.categoryTitle(category.id) : category.name).foregroundStyle(.primary)
                Spacer()
                if selection == category.id { Image(systemName: "checkmark") }
            }
            .frame(minHeight: 44)
        }
        .accessibilityAddTraits(selection == category.id ? .isSelected : [])
    }
}
