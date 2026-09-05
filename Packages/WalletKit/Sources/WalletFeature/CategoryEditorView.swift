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
                    if let color = (route.category ?? route.parent)?.colorToken {
                        LabeledContent("Color") {
                            Circle().fill(color.color).frame(width: 20, height: 20)
                                .accessibilityLabel("Fixed category color \(color.hex)")
                        }
                    }
                } footer: { Text("Use a name with 1 to 80 characters. Names must be distinct within the same category level.") }
                Section {
                    Picker("Nature", selection: $nature) {
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
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}
