import SwiftUI

/// Splits the toolbar items around it into separate glass groups on iOS 26 and later,
/// so a screen's main action gets its own circle instead of sharing a capsule with
/// unrelated controls. Earlier systems draw toolbar items apart already, so it adds nothing there.
struct WalletToolbarSeparator: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26, macOS 26, visionOS 26, watchOS 26, *) {
            ToolbarSpacer(.fixed)
        }
    }
}

extension View {
    /// Marks a toolbar button as the screen's main action: a tinted, filled glass circle on
    /// iOS 26 and later. Earlier systems keep the plain toolbar button.
    @ViewBuilder
    func walletPrimaryToolbarAction() -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, watchOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            self
        }
    }
}
