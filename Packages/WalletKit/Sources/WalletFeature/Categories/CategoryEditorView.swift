import SwiftUI
import WalletDomain

struct CategoryEditorRoute: Identifiable {
    let id = UUID()
    var category: WalletCategory?
    var parent: WalletCategory?
}

struct CategoryEditorView: View {
    @ObservedObject var viewModel: CategoriesViewModel
    let route: CategoryEditorRoute
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var nature: CategoryNature
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var choosingSymbol = false

    /// The saved category being edited, read live so a new icon shows as soon as it is chosen.
    private var editedCategory: WalletCategory? {
        route.category.map { viewModel.category(id: $0.id) ?? $0 }
    }

    init(viewModel: CategoriesViewModel, route: CategoryEditorRoute) {
        self.viewModel = viewModel
        self.route = route
        _name = State(initialValue: route.category?.name ?? "")
        _nature = State(initialValue: route.category?.nature ?? .none)
    }

    private var title: String {
        if route.category != nil { return "Edit" }
        let noun = route.parent == nil ? "Category" : "Subcategory"
        return "Create \(noun)"
    }

    /// The subcategory this sheet is editing, if that is what it is editing.
    ///
    /// Only a subcategory offers deletion here: a category is deleted from its own screen, which
    /// has the room to ask what should become of the subcategories under it.
    private var deletable: WalletCategory? {
        route.parent == nil ? nil : route.category
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let parent = route.parent { LabeledContent("Category", value: parent.name) }
                    HStack(spacing: 16) {
                        Text("Name")
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Name")
                    }
                    // The icon is saved on the category straight away, so only a saved one can have it.
                    if let category = editedCategory {
                        Button { choosingSymbol = true } label: {
                            LabeledContent("Icon") {
                                HStack(spacing: WalletMetrics.small) {
                                    CategoryIcon(category: category)
                                    WalletDisclosure()
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let color = (route.category ?? route.parent)?.colorToken {
                        LabeledContent("Color") {
                            Circle().fill(color.color).frame(width: 20, height: 20)
                                .accessibilityLabel("Fixed category color \(color.hex)")
                        }
                    }
                } footer: { Text("Use a name with 1 to 80 characters. Names must be distinct within the same category level.") }
                Section {
                    WalletMenuPicker("Nature", selection: $nature, value: nature.title) {
                        ForEach(CategoryNature.allCases) { nature in
                            Text(nature.title).tag(nature)
                        }
                    }
                } footer: {
                    Text("Choose None, Must, Need, or Want. Nature changes its badge color, not the fixed category color. Subcategories share their parent's category color but keep their own nature.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).accessibilityLabel("Error: \(errorMessage)") }
                }
                if deletable != nil {
                    Section {
                        WalletDestructiveRow(title: "Delete Subcategory") { confirmingDelete = true }
                    } footer: {
                        Text("Records using it become Uncategorized. No financial records or balances are removed.")
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(viewModel.isSaving)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            errorMessage = nil
                            do {
                                try await viewModel.save(id: route.category?.id, parentID: route.parent?.id, name: name, nature: nature)
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text(route.category == nil ? "Create" : "Save") }
                    }
                    .disabled(viewModel.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).count > 80)
                }
            }
            .alert("Delete Subcategory?", isPresented: $confirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard let deletable else { return }
                    Task {
                        errorMessage = nil
                        do {
                            // A subcategory is the bottom of the hierarchy, so there is nothing
                            // underneath it for the strategy to decide about.
                            try await viewModel.delete(id: deletable.id, strategy: .deleteSubcategories)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            } message: {
                Text("This cannot be undone. Records using \(deletable?.name ?? "it") become Uncategorized.")
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .sheet(isPresented: $choosingSymbol) {
                if let category = route.category {
                    CategorySymbolPicker(category: category, viewModel: viewModel)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
