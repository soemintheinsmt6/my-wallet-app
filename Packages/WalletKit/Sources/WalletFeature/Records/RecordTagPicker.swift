import SwiftUI
import WalletDomain

struct RecordTagPicker: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var selection: Set<UUID>

    var body: some View {
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
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
