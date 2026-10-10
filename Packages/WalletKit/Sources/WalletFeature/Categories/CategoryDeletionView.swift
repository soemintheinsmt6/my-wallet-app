import SwiftUI
import WalletDomain

struct CategoryDeletionView: View {
    @ObservedObject var viewModel: CategoriesViewModel
    let category: WalletCategory
    @Environment(\.dismiss) private var dismiss
    @State private var reassign = false
    @State private var destination: UUID?
    @State private var confirming = false
    @State private var errorMessage: String?

    private var children: [WalletCategory] { viewModel.subcategories(of: category.id) }
    private var destinations: [WalletCategory] { viewModel.rootCategories.filter { $0.id != category.id } }

    var body: some View {
        NavigationStack {
            Form {
                Text("Records using a deleted category become Uncategorized. No financial records or balances are removed.")
                if !children.isEmpty {
                    LabeledContent("Subcategories", value: "\(children.count)")
                    Toggle("Move subcategories to another category", isOn: $reassign)
                        .disabled(destinations.isEmpty)
                    if reassign {
                        WalletMenuPicker("Move to", selection: $destination,
                                         value: destinations.first { $0.id == destination }?.name ?? "Choose category") {
                            Text("Choose category").tag(nil as UUID?)
                            ForEach(destinations) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } else { Text("All subcategories will also be deleted.").foregroundStyle(.secondary) }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button("Delete Category", role: .destructive) { confirming = true }
                    .disabled(reassign && destination == nil)
            }
            .formStyle(.grouped)
            .navigationTitle("Delete \(category.name)")
            .disabled(viewModel.isSaving)
            .toolbar { Button("Cancel") { dismiss() }.disabled(viewModel.isSaving) }
            .alert("Delete Category?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            let strategy: CategoryDeletionStrategy = reassign && destination != nil
                                ? .reassignSubcategories(to: destination!) : .deleteSubcategories
                            try await viewModel.delete(id: category.id, strategy: strategy)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            } message: { Text("This cannot be undone. Records will be kept with an Uncategorized fallback where needed.") }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 380)
        #endif
    }
}
