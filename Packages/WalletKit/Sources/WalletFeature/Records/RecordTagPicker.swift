import SwiftUI
import WalletDomain

/// One label per record. Choosing a label replaces any other and returns to the form; "No label"
/// clears it. The picker closes on every choice, so tapping the current label keeps it rather
/// than silently removing it.
///
/// Records keep a set of label IDs, so older records saved with several still load and show them;
/// picking here narrows such a record to the one chosen.
struct RecordTagPicker: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Binding var selection: Set<UUID>
    /// Called after a choice. The presenter closes the picker by clearing the state that pushed it;
    /// `dismiss` is avoided because inside an editor sheet it can close the whole sheet.
    let onPicked: () -> Void

    var body: some View {
        List {
            if !viewModel.tags.isEmpty {
                row(name: "No label", symbol: "tag.slash", tint: .secondary, isOn: selection.isEmpty) {
                    selection = []
                }
                .walletFirstRow(true)
            }
            ForEach(viewModel.tags) { tag in
                row(name: tag.name, symbol: "tag.fill", tint: tag.color.tint, isOn: selection.contains(tag.id)) {
                    selection = [tag.id]
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.tags.isEmpty {
                ContentUnavailableView("No labels yet", systemImage: "tag", description: Text("Create labels in the Labels tab, then select one here."))
            }
        }
        .navigationTitle("Label")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(name: String, symbol: String, tint: Color, isOn: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            action()
            onPicked()
        } label: {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
                Text(name).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
