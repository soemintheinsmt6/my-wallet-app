import SwiftUI

/// A form row that opens a pop-up menu of options: title leading, the current value and a right
/// chevron trailing. Stands in for a menu-style `Picker`, whose up-and-down chevrons cannot be
/// restyled. The options are ordinary tagged views, and the menu still checks the current one.
struct WalletMenuPicker<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    /// What the row shows for the current selection; a `Picker` keeps its option labels private.
    let value: String
    @ViewBuilder var options: () -> Options

    init(_ title: String, selection: Binding<Selection>, value: String,
         @ViewBuilder options: @escaping () -> Options) {
        self.title = title
        _selection = selection
        self.value = value
        self.options = options
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection, content: options)
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: WalletMetrics.small) {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: WalletMetrics.small)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                WalletDisclosure()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

#Preview {
    @Previewable @State var period = "Monthly"
    Form {
        WalletMenuPicker("Period", selection: $period, value: period) {
            ForEach(["Weekly", "Monthly", "Yearly"], id: \.self) { Text($0).tag($0) }
        }
    }
}
