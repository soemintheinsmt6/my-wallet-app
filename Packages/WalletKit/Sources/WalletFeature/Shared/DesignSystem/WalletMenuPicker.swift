import SwiftUI

/// A form row that opens a pop-up menu of options: title leading, the current value and
/// up-and-down chevrons trailing. Up-and-down chevrons mean "opens a menu here"; a right chevron
/// is kept for rows that push a screen. Stands in for a menu-style `Picker` so the value reads in
/// secondary text like every other row instead of the accent color. The options are ordinary
/// tagged views, and the menu still checks the current one.
///
/// Only the trailing value and chevrons open the menu. The title sits outside it so it stays put
/// instead of fading with the menu's pressed and open states, as a menu-style `Picker` row does.
struct WalletMenuPicker<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    /// What the row shows for the current selection; a `Picker` keeps its option labels private.
    let value: String
    /// A colored symbol leading the title, in editors whose rows carry one.
    let icon: (symbol: String, color: Color)?
    @ViewBuilder var options: () -> Options

    init(_ title: String, selection: Binding<Selection>, value: String,
         icon: (symbol: String, color: Color)? = nil,
         @ViewBuilder options: @escaping () -> Options) {
        self.title = title
        _selection = selection
        self.value = value
        self.icon = icon
        self.options = options
    }

    var body: some View {
        HStack(spacing: WalletMetrics.small) {
            Group {
                if let icon {
                    WalletFormLabel(title, symbol: icon.symbol, color: icon.color)
                } else {
                    Text(title)
                }
            }
            .foregroundStyle(.primary)
            // The menu below carries the title for VoiceOver, so it is read once.
            .accessibilityHidden(true)
            Spacer(minLength: WalletMetrics.small)
            Menu {
                Picker(title, selection: $selection, content: options)
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                HStack(spacing: WalletMetrics.small) {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    WalletMenuIndicator()
                }
                // Widens a short value's target a little, without reaching the title.
                .padding(.leading, WalletMetrics.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
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
