import SwiftUI
import WalletDomain

struct TagEditorView: View {
    @ObservedObject var viewModel: TagsViewModel
    let tag: WalletTag?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: TagColor
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    init(viewModel: TagsViewModel, tag: WalletTag? = nil) {
        self.viewModel = viewModel
        self.tag = tag
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? .blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Text("Name")
                        TextField("Label name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Label name")
                    }
                } footer: { Text("Use a unique name with 1 to 80 characters, such as Work or Vacation.") }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                        ForEach(TagColor.allCases) { option in
                            Button { color = option } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(option.tint).frame(width: 36, height: 36)
                                        .overlay {
                                            if color == option {
                                                Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                            }
                                        }
                                    Text(option.title).font(.caption).foregroundStyle(.primary)
                                }
                                .frame(minWidth: 44, minHeight: 60)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityAddTraits(color == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                if tag != nil {
                    Section {
                        Button("Delete Label", role: .destructive) { confirmingDelete = true }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).accessibilityLabel("Error: \(errorMessage)") }
                }
            }
            .formStyle(.grouped)
            .disabled(viewModel.isSaving)
            .navigationTitle(tag == nil ? "Create Label" : "Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if viewModel.isSaving { ProgressView() } else { Text(tag == nil ? "Create" : "Save") }
                    }
                    .disabled(viewModel.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).count > 80)
                }
            }
            .confirmationDialog("Delete Label?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let tag else { return }
                    Task {
                        errorMessage = nil
                        do {
                            try await viewModel.delete(id: tag.id)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Delete \"\(tag?.name ?? "")\"? This cannot be undone.") }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }

    private func save() async {
        errorMessage = nil
        do {
            try await viewModel.save(id: tag?.id, name: name, color: color)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
