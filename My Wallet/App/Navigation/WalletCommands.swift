import SwiftUI
import WalletDomain
import WalletFeature

/// Menu bar and hardware-keyboard shortcuts.
///
/// Present on macOS and on iPad with a keyboard attached; iPhone simply never surfaces them. The
/// commands post through `WalletCommandBus` rather than reaching into a window directly, because
/// a scene's commands are built once while the windows acting on them come and go.
struct WalletCommands: Commands {
    @ObservedObject var commands: WalletCommandBus

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Expense") { commands.newRecord(kind: .expense) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Income") { commands.newRecord(kind: .income) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Transfer") { commands.newRecord(kind: .transfer) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Find Records") { commands.show(.records); commands.search() }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            // ⌘1…⌘5 match the sidebar and tab order.
            ForEach(Array(WalletTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { commands.show(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
