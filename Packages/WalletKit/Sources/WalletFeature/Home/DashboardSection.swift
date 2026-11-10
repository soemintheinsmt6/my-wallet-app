import SwiftUI

/// One card of the Dashboard: an optional header, then its content on a rounded card, with a rule
/// between rows as a list section draws them.
///
/// The Dashboard draws its own cards rather than using a grouped `List`, because from iOS 26 the
/// system rounds list sections to about 30 points and clips any card placed edge to edge inside one
/// to that too. Drawing them here gives every card, and the account and quick-action cards set
/// inside a bare section, the one radius `WalletMetrics.cardRadius`.
struct DashboardSection<Content: View, Header: View>: View {
    /// Content that draws its own cards, such as the account grid, laid out without a card behind it.
    var isBare = false
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header

    init(isBare: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.isBare = isBare
        self.content = content()
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            header
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, WalletMetrics.xLarge)
            if isBare {
                content
            } else {
                _VariadicView.Tree(DividedRows()) { content }
                    .padding(.horizontal, WalletMetrics.xLarge)
                    .padding(.vertical, WalletMetrics.tight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.walletCard,
                                in: RoundedRectangle(cornerRadius: WalletMetrics.cardRadius, style: .continuous))
            }
        }
    }
}

extension DashboardSection where Header == EmptyView {
    init(isBare: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(isBare: isBare, content: content) { EmptyView() }
    }
}

extension DashboardSection where Header == Text {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { Text(title) }
    }
}

/// Lays a section's rows out one under another, each padded as a list row is, with a rule between
/// consecutive rows and none after the last.
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                    .padding(.vertical, WalletMetrics.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if child.id != last { Divider() }
            }
        }
    }
}
