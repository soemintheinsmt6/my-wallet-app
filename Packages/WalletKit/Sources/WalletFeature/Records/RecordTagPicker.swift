import SwiftUI
import WalletDomain

struct RecordTagPicker: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.tags) { tag in
                Button {
                    if selection.contains(tag.id) { selection.remove(tag.id) } else { selection.insert(tag.id) }
                } label: {
                    HStack {
                        Image(systemName: "tag.fill").foregroundStyle(tag.color.tint)
                        Text(tag.name).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(tag.id) { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityAddTraits(selection.contains(tag.id) ? .isSelected : [])
            }
            .overlay {
                if viewModel.tags.isEmpty {
                    ContentUnavailableView("No labels yet", systemImage: "tag", description: Text("Create labels in the Labels tab, then select them here."))
                }
            }
            .navigationTitle("Labels")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 440)
        #endif
    }
}
