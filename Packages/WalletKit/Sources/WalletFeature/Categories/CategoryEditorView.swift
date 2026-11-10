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
    @State private var editingName = false

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

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Fixed by the category, or by its parent for a subcategory; gray until a new category has one.
    private var categoryColor: Color { (route.category ?? route.parent)?.colorToken.color ?? .gray }

    private static let nameCaption = "Use a name with 1 to 80 characters. Names must be distinct within the same category level."
    private static let natureCaption = "Choose None, Must, Need, or Want. Nature changes its badge color, not the fixed "
        + "category color. Subcategories share their parent's category color but keep their own nature."

    var body: some View {
        NavigationStack {
            // The record editor's layout: section headings over rows, text on its own screen.
            ScrollView {
                VStack(spacing: 0) {
                    generalSection
                    WalletEditorSectionHeader(title: "Nature")
                    RecordFormRow(symbol: "tag", showsDivider: false) {
                        WalletMenuPicker("Nature", selection: $nature, value: nature.title) {
                            ForEach(CategoryNature.allCases) { nature in
                                Text(nature.title).tag(nature)
                            }
                        }
                    }
                    WalletEditorCaption(Self.natureCaption)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding(20)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                    if deletable != nil {
                        WalletEditorDeleteButton(title: "Delete Subcategory") { confirmingDelete = true }
                        WalletEditorCaption("Records using it become Uncategorized. No financial records or balances are removed.")
                    }
                }
                .walletEditorRows()
            }
            .walletEditorPage()
            .disabled(viewModel.isSaving)
            .navigationTitle(title)
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $editingName) {
                RecordTextEntry(title: "Name", text: $name,
                                caption: route.parent == nil ? "Name this category" : "Name this subcategory")
            }
            // Pinned at the bottom like the record and account editors' Save.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                WalletEditorBottomButton(
                    title: route.category == nil ? "Create" : "Save", isBusy: viewModel.isSaving,
                    isEnabled: !viewModel.isSaving && !trimmedName.isEmpty && trimmedName.count <= 80
                ) { save() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
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

    /// Every row leads with a tile, so the section's icons match: the parent's own tile, the name
    /// and color in the category's color, and the icon itself.
    @ViewBuilder private var generalSection: some View {
        WalletEditorSectionHeader(title: "General")
        if let parent = route.parent {
            RecordFormRow(symbol: "folder", category: parent, categoryTile: true) {
                Text("Category")
                Spacer()
                Text(parent.name).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minHeight: 44)
        }
        RecordFormRow(symbol: "textformat", color: categoryColor, filledIcon: true) {
            WalletEditorNavigationButton(title: "Name", value: trimmedName.isEmpty ? nil : trimmedName) {
                editingName = true
            }
        }
        // The icon is saved on the category straight away, so only a saved one can have it.
        if let category = editedCategory {
            RecordFormRow(symbol: category.symbol, category: category, categoryTile: true) {
                WalletEditorNavigationButton(title: "Icon", value: nil) { choosingSymbol = true }
            }
        }
        // Fixed, so a value rather than a choice: no chevron.
        RecordFormRow(symbol: "paintpalette.fill", color: categoryColor, filledIcon: true, showsDivider: false) {
            Text("Color")
            Spacer()
            Text(route.parent == nil ? "Fixed" : "Same as \(route.parent?.name ?? "parent")")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        WalletEditorCaption(Self.nameCaption)
    }

    private func save() {
        Task {
            errorMessage = nil
            do {
                try await viewModel.save(id: route.category?.id, parentID: route.parent?.id, name: name, nature: nature)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
