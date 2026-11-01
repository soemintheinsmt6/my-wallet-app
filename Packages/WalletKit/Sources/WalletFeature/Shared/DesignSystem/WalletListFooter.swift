import SwiftUI

/// Explanatory text under a section of a flat (plain) list.
///
/// Inset lists style footers as small secondary text on their own, but a plain list draws them at
/// body size, where a sentence of explanation reads like a row of content. This keeps footers a
/// caption whichever list style the screen uses. It also wraps on macOS, whose lists otherwise
/// cut a footer to one truncated line.
struct WalletListFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, WalletMetrics.tight)
    }
}

extension View {
    /// A flat list draws a rule above its first row, which lands right under the large title and
    /// reads as a stray line. Pass `true` for the first row of a list that starts without a header.
    func walletFirstRow(_ isFirst: Bool) -> some View {
        listRowSeparator(isFirst ? .hidden : .automatic, edges: .top)
    }
}
